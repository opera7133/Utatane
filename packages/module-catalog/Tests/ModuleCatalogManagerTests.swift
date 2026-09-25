import CryptoKit
import Foundation
import Testing
@testable import UtataneModuleCatalog
import UtataneNetwork
import ZIPFoundation

@Test func `signed HTTP catalog installs SAORI and rejects changed ZIP`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "catalog-http-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = Data("SAORI binary".utf8)
    let manifest = Data("""
    {"schemaVersion":1,"id":"wmove","version":"1.0.0","revision":1,"abi":"saori-1","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libwmove.dylib":"\(catalogDigest(library))"}}
    """.utf8)
    let zip = root.appending(path: "wmove.zip")
    let archive = try Archive(url: zip, accessMode: .create)
    for (path, data) in [("wmove/lib/libwmove.dylib", library), ("wmove/module.json", manifest)] {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return start < end ? data.subdata(in: start ..< end) : Data()
        }
    }
    let zipBytes = try Data(contentsOf: zip)
    let index = Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[{"id":"wmove","displayName":"wmove","kinds":["saori"],"availability":"candidate","artifacts":[{"path":"artifacts/wmove.zip","sha256":"\(catalogDigest(zipBytes))","size":\(zipBytes.count),"architectures":["arm64"],"minimumOS":"14.0","abi":"saori-1","version":"1.0.0","revision":1}]}]}
    """.utf8)
    let key = Curve25519.Signing.PrivateKey()
    let signature = try key.signature(for: index)
    let url = try #require(URL(string: "https://example.test/modules/index.json"))
    let client = SignedModuleCatalogClient(indexURL: url, publicKey: key.publicKey.rawRepresentation)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ModuleCatalogURLProtocol.self]
    let session = URLSession(configuration: configuration)
    ModuleCatalogURLProtocol.setResponses(["index.json": index, "index.sig": signature, "wmove.zip": zipBytes])
    defer { ModuleCatalogURLProtocol.setResponses([:]) }
    let manager = ModuleCatalogManager(
        client: client,
        applicationSupportURL: root.appending(path: "Application Support/Utatane"),
        architecture: "arm64",
        macOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    )
    let olderSystem = ModuleCatalogManager(
        client: client,
        applicationSupportURL: root.appending(path: "Application Support/Utatane"),
        architecture: "arm64",
        macOSVersion: OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)
    )
    await #expect(throws: ModuleCatalogInstallError.unsupportedPlatform) {
        try await olderSystem.install(moduleID: "wmove", session: session)
    }
    let destination = try await manager.install(moduleID: "wmove", session: session)
    #expect(destination.path.contains("/NativeSaori/wmove"))
    #expect(try Data(contentsOf: destination.appending(path: "lib/libwmove.dylib")) == library)

    ModuleCatalogURLProtocol.setResponses(["index.json": index, "index.sig": signature, "wmove.zip": Data("changed".utf8)])
    await #expect(throws: ModuleCatalogError.artifactMismatch) {
        try await manager.install(moduleID: "wmove", session: session)
    }
    #expect(try Data(contentsOf: destination.appending(path: "lib/libwmove.dylib")) == library)
}

private func catalogDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private final class ModuleCatalogURLProtocol: URLProtocol {
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
