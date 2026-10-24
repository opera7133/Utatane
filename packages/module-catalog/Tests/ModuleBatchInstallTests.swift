import CryptoKit
import Foundation
import Testing
@testable import UtataneModuleCatalog
import UtataneNetwork
import ZIPFoundation

@Test func `a signed mixed batch resumes after failure without downloading installed modules again`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var responses: [String: Data] = [:], entries: [[String: Any]] = []
    for (id, kind) in [("probe-shiori", "shiori"), ("probe-saori", "saori")] {
        let library = Data((id + " bytes").utf8), libraryPath = "lib/lib\(id).dylib"
        let manifest = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "id": id, "version": "1", "revision": 1, "abi": "test", "minimumOS": "14.0", "architectures": ["arm64"], "files": [libraryPath: batchHash(library)]])
        let url = root.appending(path: id + ".zip"), archive = try Archive(url: url, accessMode: .create)
        for (path, data) in [(libraryPath, library), ("module.json", manifest)] {
            try archive.addEntry(with: id + "/" + path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position) ..< min(Int(position) + size, data.count))
            }
        }
        let bytes = try Data(contentsOf: url)
        responses[id + ".zip"] = bytes
        entries.append(["id": id, "displayName": id, "kinds": [kind], "availability": "candidate", "artifacts": [["path": "artifacts/\(id).zip", "size": bytes.count, "sha256": batchHash(bytes), "architectures": ["arm64"], "minimumOS": "14.0", "abi": "test", "version": "1", "revision": 1]]])
    }
    let key = Curve25519.Signing.PrivateKey()
    let index = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "channel": "stable", "signed": true, "modules": entries])
    responses["index.json"] = index; responses["index.sig"] = try key.signature(for: index)
    let url = try #require(URL(string: "https://batch.invalid/index.json"))
    let client = SignedModuleCatalogClient(indexURL: url, publicKey: key.publicKey.rawRepresentation)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BatchCatalogProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); BatchCatalogProtocol.configure([:]) }
    let manager = ModuleCatalogManager(client: client, applicationSupportURL: root.appending(path: "managed"), architecture: "arm64", macOSVersion: .init(majorVersion: 14, minorVersion: 0, patchVersion: 0))
    var broken = responses; broken["probe-saori.zip"] = Data("tampered".utf8)
    BatchCatalogProtocol.configure(broken)
    let catalog = try await client.fetch(session: session)
    do {
        _ = try await manager.install(moduleIDs: ["probe-shiori", "probe-saori", "probe-shiori"], catalog: catalog, session: session)
        Issue.record("tampered archive installed")
    } catch let error as ModuleBatchInstallFailure { #expect(error.moduleID == "probe-saori") }
    let inventory = ModuleCatalogInventory(applicationSupportURL: manager.applicationSupportURL, architecture: "arm64", macOSVersion: manager.macOSVersion)
    #expect(inventory.isInstalled(moduleID: "probe-shiori", kind: "shiori"))
    #expect(!inventory.isInstalled(moduleID: "probe-saori", kind: "saori"))
    BatchCatalogProtocol.configure(responses, resetRequests: false)
    let installed = try await manager.install(moduleIDs: ["probe-shiori", "probe-saori"], catalog: catalog, session: session)
    #expect(installed.count == 1)
    #expect(inventory.isInstalled(moduleID: "probe-saori", kind: "saori"))
    #expect(BatchCatalogProtocol.requests.filter { $0 == "probe-shiori.zip" }.count == 1)
    #expect(BatchCatalogProtocol.requests.filter { $0 == "index.json" }.count == 1)
    #expect(BatchCatalogProtocol.requests.filter { $0 == "probe-saori.zip" }.count == 2)
}

private func batchHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private final class BatchCatalogProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses: [String: Data] = [:]
    private nonisolated(unsafe) static var requested: [String] = []
    static var requests: [String] {
        lock.withLock { requested }
    }

    static func configure(_ values: [String: Data], resetRequests: Bool = true) {
        lock.withLock {
            responses = values; if resetRequests {
                requested = []
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let data = Self.lock.withLock { Self.requested.append(request.url!.lastPathComponent); return Self.responses[request.url!.lastPathComponent] }
        let response = HTTPURLResponse(url: request.url!, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
