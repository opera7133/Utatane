import CryptoKit
import Foundation
import Testing
@testable import UtataneNetwork

@Test func `signed module catalog verifies bytes before decoding`() throws {
    let key = Curve25519.Signing.PrivateKey()
    let url = try #require(URL(string: "https://example.test/modules/index.json"))
    let client = SignedModuleCatalogClient(
        indexURL: url,
        publicKey: key.publicKey.rawRepresentation
    )
    let index = Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[{"id":"wmove","displayName":"wmove","kinds":["saori"],"windowsFilenames":["wmove.dll"],"availability":"candidate","license":"MIT","licenseURL":"https://github.com/example/wmove/blob/main/LICENSE","instructions":"docs/wmove.md","limitations":["Sample note"],"upstream":{"url":"https://github.com/example/wmove","author":"Example"},"artifacts":[{"path":"artifacts/wmove.zip","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":12,"architectures":["arm64"],"minimumOS":"14.0","abi":"saori-1","version":"1.0.0","revision":1}]}]}
    """.utf8)
    let signature = try key.signature(for: index)
    let catalog = try client.verify(index: index, signature: signature)
    #expect(catalog.modules.map(\.id) == ["wmove"])
    #expect(catalog.modules[0].upstream?.author == "Example")
    #expect(catalog.modules[0].instructions == "docs/wmove.md")
    #expect(catalog.modules[0].limitations == ["Sample note"])
    #expect(catalog.modules[0].windowsFilenames == ["wmove.dll"])
    let unsafeDLL = Data(String(decoding: index, as: UTF8.self)
        .replacingOccurrences(of: "wmove.dll", with: "../wmove.dll").utf8)
    #expect(throws: ModuleCatalogError.invalidCatalog) {
        try client.verify(index: unsafeDLL, signature: key.signature(for: unsafeDLL))
    }
    let staging = Data(String(decoding: index, as: UTF8.self).replacingOccurrences(of: "\"stable\"", with: "\"staging\"").utf8)
    let stagingSignature = try key.signature(for: staging)
    #expect(throws: ModuleCatalogError.invalidCatalog) {
        try client.verify(index: staging, signature: stagingSignature)
    }
    let previewClient = SignedModuleCatalogClient(indexURL: url, publicKey: key.publicKey.rawRepresentation,
                                                  allowsStaging: true)
    #expect(try previewClient.verify(index: staging, signature: stagingSignature).channel == "staging")
    #expect(throws: ModuleCatalogError.invalidSignature) {
        try client.verify(index: index + Data(" ".utf8), signature: signature)
    }
    #expect(throws: ModuleCatalogError.invalidSignature) {
        try SignedModuleCatalogClient(indexURL: client.indexURL, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
            .verify(index: index, signature: signature)
    }
}

@Test func `signed module catalog rejects unsafe artifact path`() throws {
    let key = Curve25519.Signing.PrivateKey()
    let url = try #require(URL(string: "https://example.test/modules/index.json"))
    let client = SignedModuleCatalogClient(
        indexURL: url,
        publicKey: key.publicKey.rawRepresentation
    )
    let index = Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[{"id":"wmove","displayName":"wmove","kinds":["saori"],"availability":"candidate","artifacts":[{"path":"artifacts/../bad.zip","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":12,"architectures":["arm64"],"minimumOS":"14.0","abi":"saori-1","version":"1.0.0","revision":1}]}]}
    """.utf8)
    #expect(throws: ModuleCatalogError.invalidCatalog) {
        try client.verify(index: index, signature: key.signature(for: index))
    }
}

@Suite(.serialized)
struct SignedCatalogDownloadTests {
    @Test(arguments: [false, true])
    func `signed module catalog fetches both HTTP files`(allowsStaging: Bool) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let archive = Data("sample archive".utf8)
        let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        let index = Data("""
        {"schemaVersion":1,"channel":"\(allowsStaging ? "staging" : "stable")","signed":true,"modules":[{"id":"wmove","displayName":"wmove","kinds":["saori"],"availability":"candidate","artifacts":[{"path":"artifacts/wmove.zip","sha256":"\(hash)","size":\(archive.count),"architectures":["arm64"],"minimumOS":"14.0","abi":"saori-1","version":"1.0.0","revision":1}]}]}
        """.utf8)
        let signature = try key.signature(for: index)
        let url = try #require(URL(string: "https://example.test/modules/index.json"))
        let client = SignedModuleCatalogClient(indexURL: url, publicKey: key.publicKey.rawRepresentation,
                                               allowsStaging: allowsStaging)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        let session = URLSession(configuration: configuration)
        CatalogURLProtocol.setResponses(["index.json": index, "index.sig": signature, "wmove.zip": archive])
        defer { CatalogURLProtocol.setResponses([:]) }
        let catalog = try await client.fetch(session: session)
        #expect(catalog.modules.map(\.id) == ["wmove"])
        let destination = FileManager.default.temporaryDirectory.appending(path: "wmove-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await client.downloadArtifact(moduleID: "wmove", artifactIndex: 0, catalog: catalog,
                                          to: destination, session: session)
        #expect(try Data(contentsOf: destination) == archive)
        CatalogURLProtocol.setResponses(["wmove.zip": Data("changed".utf8)])
        let rejected = FileManager.default.temporaryDirectory.appending(path: "wmove-\(UUID().uuidString).zip")
        await #expect(throws: ModuleCatalogError.artifactMismatch) {
            try await client.downloadArtifact(moduleID: "wmove", artifactIndex: 0, catalog: catalog,
                                              to: rejected, session: session)
        }
        #expect(!FileManager.default.fileExists(atPath: rejected.path))
    }
}

private final class CatalogURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses: [String: Data] = [:]

    static func setResponses(_ values: [String: Data]) {
        lock.withLock { responses = values }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let name = request.url?.lastPathComponent ?? ""
        let data = Self.lock.withLock { Self.responses[name] }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200,
                                             httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: ModuleCatalogError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
