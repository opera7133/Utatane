import CryptoKit
import Foundation

public enum ModuleCatalogError: Error, Equatable {
    case invalidEndpoint
    case invalidResponse
    case tooLarge
    case invalidSignature
    case invalidCatalog
    case missingArtifact
    case artifactMismatch
    case destinationExists
}

public struct SignedModuleCatalog: Decodable, Sendable {
    public struct Module: Decodable, Sendable, Identifiable {
        public struct Upstream: Decodable, Sendable {
            public let url: String
            public let author: String
        }

        private struct Metadata: Sendable {
            let license: String?
            let licenseURL: String?
            let originalURL: String?
            let upstream: Upstream?
            let origin: String?
            let instructions: String?
            let limitations: [String]?
        }

        public struct Artifact: Decodable, Sendable {
            public let path: String
            public let sha256: String
            public let size: Int
            public let architectures: [String]
            public let minimumOS: String
            public let abi: String
            public let version: String
            public let revision: Int
        }

        public let id: String
        public let displayName: String
        public let kinds: [String]
        public let windowsFilenames: [String]
        public var license: String? {
            metadata.license
        }

        public var licenseURL: String? {
            metadata.licenseURL
        }

        public var originalURL: String? {
            metadata.originalURL
        }

        public var upstream: Upstream? {
            metadata.upstream
        }

        public var origin: String? {
            metadata.origin
        }

        public var instructions: String? {
            metadata.instructions
        }

        public var limitations: [String]? {
            metadata.limitations
        }

        public let availability: String
        public let artifacts: [Artifact]
        private let metadata: Metadata

        private enum CodingKeys: String, CodingKey {
            case id, displayName, kinds, windowsFilenames, license, licenseURL, originalURL, upstream, origin
            case instructions, limitations, availability, artifacts
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            displayName = try values.decode(String.self, forKey: .displayName)
            kinds = try values.decode([String].self, forKey: .kinds)
            windowsFilenames = try values.decodeIfPresent([String].self, forKey: .windowsFilenames) ?? []
            metadata = try Metadata(
                license: values.decodeIfPresent(String.self, forKey: .license),
                licenseURL: values.decodeIfPresent(String.self, forKey: .licenseURL),
                originalURL: values.decodeIfPresent(String.self, forKey: .originalURL),
                upstream: values.decodeIfPresent(Upstream.self, forKey: .upstream),
                origin: values.decodeIfPresent(String.self, forKey: .origin),
                instructions: values.decodeIfPresent(String.self, forKey: .instructions),
                limitations: values.decodeIfPresent([String].self, forKey: .limitations)
            )
            availability = try values.decode(String.self, forKey: .availability)
            artifacts = try values.decode([Artifact].self, forKey: .artifacts)
        }
    }

    public let schemaVersion: Int
    public let channel: String
    public let signed: Bool
    public let modules: [Module]
}

/// Reads the catalog's HTTP index. The caller supplies the distribution URL and pinned Ed25519 public key.
public struct SignedModuleCatalogClient: Sendable {
    public let indexURL: URL
    public let publicKey: Data
    public let allowsStaging: Bool

    public init(indexURL: URL, publicKey: Data) {
        self.init(indexURL: indexURL, publicKey: publicKey, allowsStaging: false)
    }

    public init(indexURL: URL, publicKey: Data, allowsStaging: Bool) {
        self.indexURL = indexURL
        self.publicKey = publicKey
        self.allowsStaging = allowsStaging
    }

    public func fetch(session: URLSession = .shared) async throws -> SignedModuleCatalog {
        guard indexURL.scheme == "https", indexURL.lastPathComponent == "index.json",
              indexURL.query == nil, indexURL.fragment == nil
        else { throw ModuleCatalogError.invalidEndpoint }
        let signatureURL = indexURL.deletingLastPathComponent().appending(path: "index.sig")
        let (index, indexResponse) = try await session.data(from: indexURL)
        let (signature, signatureResponse) = try await session.data(from: signatureURL)
        guard (indexResponse as? HTTPURLResponse)?.statusCode == 200,
              (signatureResponse as? HTTPURLResponse)?.statusCode == 200
        else { throw ModuleCatalogError.invalidResponse }
        return try verify(index: index, signature: signature)
    }

    public func verify(index: Data, signature: Data) throws -> SignedModuleCatalog {
        guard index.count <= 2_000_000 else { throw ModuleCatalogError.tooLarge }
        guard signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: index)
        else { throw ModuleCatalogError.invalidSignature }
        guard let catalog = try? JSONDecoder().decode(SignedModuleCatalog.self, from: index),
              catalog.schemaVersion == 1,
              acceptsChannel(catalog.channel),
              catalog.signed,
              !catalog.modules.isEmpty
        else { throw ModuleCatalogError.invalidCatalog }
        var identifiers = Set<String>()
        for module in catalog.modules {
            guard isIdentifier(module.id), identifiers.insert(module.id).inserted,
                  !module.displayName.isEmpty, !module.kinds.isEmpty,
                  module.kinds.allSatisfy({ ["shiori", "saori", "plugin"].contains($0) }),
                  module.windowsFilenames.allSatisfy(isSafeDLLFilename),
                  ["candidate", "instructions-only"].contains(module.availability),
                  (module.availability == "candidate") == !module.artifacts.isEmpty,
                  module.instructions == nil || isDocumentPath(module.instructions!),
                  module.licenseURL == nil || module.licenseURL?.hasPrefix("https://") == true
            else { throw ModuleCatalogError.invalidCatalog }
            for artifact in module.artifacts {
                guard isArtifactPath(artifact.path), artifact.sha256.count == 64,
                      artifact.sha256.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }),
                      artifact.size > 0, !artifact.architectures.isEmpty,
                      artifact.architectures.allSatisfy({ ["arm64", "x86_64"].contains($0) }),
                      !artifact.abi.isEmpty, !artifact.version.isEmpty, artifact.revision > 0
                else { throw ModuleCatalogError.invalidCatalog }
            }
        }
        return catalog
    }

    /// Downloads one artifact from an already verified catalog. The caller chooses a new ZIP path.
    public func downloadArtifact(
        moduleID: String,
        artifactIndex: Int,
        catalog: SignedModuleCatalog,
        to destination: URL,
        session: URLSession = .shared
    ) async throws {
        guard indexURL.scheme == "https", indexURL.lastPathComponent == "index.json",
              acceptsChannel(catalog.channel), catalog.signed,
              let module = catalog.modules.first(where: { $0.id == moduleID }),
              module.artifacts.indices.contains(artifactIndex)
        else { throw ModuleCatalogError.missingArtifact }
        let artifact = module.artifacts[artifactIndex]
        guard isArtifactPath(artifact.path), artifact.size > 0, artifact.size <= 512_000_000,
              destination.isFileURL
        else { throw ModuleCatalogError.invalidCatalog }
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw ModuleCatalogError.destinationExists }
        let url = indexURL.deletingLastPathComponent().appending(path: artifact.path)
        let (temporary, response) = try await session.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModuleCatalogError.invalidResponse
        }
        let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard bytes.count == artifact.size, digest == artifact.sha256 else {
            throw ModuleCatalogError.artifactMismatch
        }
        guard !manager.fileExists(atPath: destination.path) else { throw ModuleCatalogError.destinationExists }
        try manager.moveItem(at: temporary, to: destination)
    }

    private func isIdentifier(_ value: String) -> Bool {
        guard let first = value.utf8.first, (97 ... 122).contains(first) else { return false }
        return value.utf8.allSatisfy { (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 45 || $0 == 46 }
    }

    private func isSafeDLLFilename(_ value: String) -> Bool {
        value == URL(filePath: value).lastPathComponent && value.lowercased().hasSuffix(".dll")
            && !value.contains("\\") && !value.contains(":") && !value.contains("\0")
    }

    private func acceptsChannel(_ channel: String) -> Bool {
        channel == "stable" || (allowsStaging && channel == "staging")
    }

    private func isArtifactPath(_ value: String) -> Bool {
        guard value.hasPrefix("artifacts/"), value.hasSuffix(".zip"),
              !value.contains("\\"), !value.contains(":") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[1].isEmpty && parts.allSatisfy { $0 != "." && $0 != ".." }
    }

    private func isDocumentPath(_ value: String) -> Bool {
        guard value.hasPrefix("docs/"), value.hasSuffix(".md"), !value.contains("\\"), !value.contains(":") else {
            return false
        }
        return value.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
