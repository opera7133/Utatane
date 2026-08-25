import Foundation
@preconcurrency import Network

public struct NetworkStatusSnapshot: Sendable, Equatable {
    public let isOnline: Bool
    public let addresses: [String]
    public let interfaceType: String
    public let isExpensive: Bool

    public init(isOnline: Bool, addresses: [String], interfaceType: String, isExpensive: Bool) {
        self.isOnline = isOnline
        self.addresses = addresses
        self.interfaceType = interfaceType
        self.isExpensive = isExpensive
    }

    public var references: [Int: String] {
        [
            0: isOnline ? "online" : "offline",
            1: addresses.joined(separator: "\u{1}"),
            2: isOnline ? interfaceType : "none",
            3: "0",
            4: "0",
            5: isExpensive ? "fixed" : "unrestricted"
        ]
    }
}

@MainActor
public final class NetworkStatusMonitor {
    public var onChange: (@MainActor (NetworkStatusSnapshot) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.utatane.network-status")
    private var previous: NetworkStatusSnapshot?

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = NetworkStatusSnapshot(
                isOnline: path.status == .satisfied,
                addresses: Host.current().addresses.filter { !$0.contains(":") || $0 != "::1" }
                    .filter { $0 != "127.0.0.1" }.sorted(),
                interfaceType: Self.interfaceType(path),
                isExpensive: path.isExpensive
            )
            Task { @MainActor [weak self] in
                guard let self, snapshot != previous else { return }
                previous = snapshot
                onChange?(snapshot)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    private nonisolated static func interfaceType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "wifi"
        }
        if path.usesInterfaceType(.wiredEthernet) {
            return "ethernet"
        }
        if path.usesInterfaceType(.cellular) {
            return "cellular"
        }
        if path.status == .satisfied {
            return "other"
        }
        return "none"
    }
}

public struct RecycleBinSnapshot: Sendable, Equatable {
    public let itemCount: Int
    public let totalBytes: Int64

    public init(itemCount: Int, totalBytes: Int64) {
        self.itemCount = itemCount
        self.totalBytes = totalBytes
    }

    public func references(previous: RecycleBinSnapshot?) -> [Int: String] {
        [
            0: String(itemCount),
            1: String(totalBytes),
            2: String(itemCount - (previous?.itemCount ?? itemCount)),
            3: String(totalBytes - (previous?.totalBytes ?? totalBytes)),
            4: "1",
            5: ""
        ]
    }
}

public struct MacOSRecycleBinSampler: Sendable {
    public init() {}

    public func sample() -> RecycleBinSnapshot? {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".Trash",
            directoryHint: .isDirectory
        )
        guard let enumerator = FileManager.default.enumerator(
            at: trash,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return nil }
        var count = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true
            else { continue }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return RecycleBinSnapshot(itemCount: count, totalBytes: bytes)
    }
}
