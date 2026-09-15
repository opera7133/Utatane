import Darwin
import Foundation
import OSLog

public enum IPMessengerProtocol {
    public static let defaultPort: UInt16 = 2425
    public static let maximumDatagramBytes = 65507

    public static let commandMask: UInt32 = 0x0000_00FF
    public static let optionMask: UInt32 = 0xFFFF_FF00

    public static let noOperation: UInt32 = 0x0000_0000
    public static let broadcastEntry: UInt32 = 0x0000_0001
    public static let broadcastExit: UInt32 = 0x0000_0002
    public static let answerEntry: UInt32 = 0x0000_0003
    public static let broadcastAbsence: UInt32 = 0x0000_0004
    public static let sendMessage: UInt32 = 0x0000_0020
    public static let receiveMessage: UInt32 = 0x0000_0021
    public static let getInfo: UInt32 = 0x0000_0040
    public static let sendInfo: UInt32 = 0x0000_0041

    public static let sendCheckOption: UInt32 = 0x0000_0100
    public static let broadcastOption: UInt32 = 0x0000_0400
    public static let autoReplyOption: UInt32 = 0x0000_2000
    public static let fileAttachmentOption: UInt32 = 0x0020_0000
    public static let encryptionOption: UInt32 = 0x0040_0000
    public static let utf8Option: UInt32 = 0x0080_0000
    public static let utf8CapabilityOption: UInt32 = 0x0100_0000

    public static func encode(_ packet: IPMessengerPacket) throws -> Data {
        let mode = packet.mode
        let usesUTF8 = packet.command & utf8Option != 0
        let header = "1:\(packet.packetNumber):\(sanitize(packet.userName)):\(sanitize(packet.hostName)):\(packet.command):"

        if isEntryMode(mode) {
            var data = legacyData(header + packet.additional)
            data.append(0)
            data.append(legacyData(packet.groupName ?? ""))
            if packet.command & utf8CapabilityOption != 0 {
                data.append(0)
                data.append(0x0A)
                data.append(Data(utf8EntryMetadata(for: packet).utf8))
            }
            guard data.count <= maximumDatagramBytes else { throw IPMessengerError.messageTooLarge }
            return data
        }

        let data = usesUTF8 ? Data((header + packet.additional).utf8) : legacyData(header + packet.additional)
        guard data.count <= maximumDatagramBytes else { throw IPMessengerError.messageTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> IPMessengerPacket {
        guard !data.isEmpty, data.count <= maximumDatagramBytes else {
            throw data.isEmpty ? IPMessengerError.invalidPacket : IPMessengerError.messageTooLarge
        }
        let bytes = [UInt8](data)
        var separators: [Int] = []
        for (index, byte) in bytes.enumerated() where byte == 0x3A {
            separators.append(index)
            if separators.count == 5 {
                break
            }
        }
        guard separators.count == 5 else { throw IPMessengerError.invalidPacket }

        func field(_ index: Int) -> Data {
            let lower = index == 0 ? 0 : separators[index - 1] + 1
            return Data(bytes[lower ..< separators[index]])
        }

        guard ascii(field(0)) == "1",
              let packetNumber = UInt64(ascii(field(1))),
              let command = UInt32(ascii(field(4)))
        else { throw IPMessengerError.invalidPacket }

        let mode = command & commandMask
        let usesUTF8 = command & utf8Option != 0
        let fieldEncoding: String.Encoding = usesUTF8 ? .utf8 : .shiftJIS
        var userName = decode(field(2), encoding: fieldEncoding)
        var hostName = decode(field(3), encoding: fieldEncoding)
        let remainder = Data(bytes[(separators[4] + 1)...])
        let components = splitNullSeparated(remainder)
        var additional = decode(components.first ?? Data(), encoding: fieldEncoding)
        var groupName: String?

        if isEntryMode(mode) {
            additional = decode(components.first ?? Data(), encoding: .shiftJIS)
            if components.count >= 2 {
                groupName = decode(components[1], encoding: .shiftJIS)
            }
            if components.count >= 3 {
                let metadataData = components.dropFirst(2).reduce(into: Data()) { result, component in
                    if !result.isEmpty {
                        result.append(0)
                    }
                    result.append(component)
                }
                let metadata = utf8Metadata(metadataData)
                userName = metadata["UN"] ?? userName
                hostName = metadata["HN"] ?? hostName
                additional = metadata["NN"] ?? additional
                groupName = metadata["GN"] ?? groupName
            }
        }

        guard !userName.isEmpty, !hostName.isEmpty else { throw IPMessengerError.invalidPacket }
        return IPMessengerPacket(
            packetNumber: packetNumber,
            userName: userName,
            hostName: hostName,
            command: command,
            additional: additional,
            groupName: groupName
        )
    }

    private static func isEntryMode(_ mode: UInt32) -> Bool {
        [broadcastEntry, broadcastExit, answerEntry, broadcastAbsence].contains(mode)
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: ":", with: ";")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func legacyData(_ value: String) -> Data {
        value.data(using: .shiftJIS, allowLossyConversion: true) ?? Data(value.utf8)
    }

    private static func decode(_ data: Data, encoding: String.Encoding) -> String {
        String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? ""
    }

    private static func ascii(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func splitNullSeparated(_ data: Data) -> [Data] {
        [UInt8](data).split(separator: 0, omittingEmptySubsequences: false).map { Data($0) }
    }

    private static func utf8EntryMetadata(for packet: IPMessengerPacket) -> String {
        [
            "UN:\(packet.userName)",
            "HN:\(packet.hostName)",
            "NN:\(packet.additional)",
            "GN:\(packet.groupName ?? "")"
        ].joined(separator: "\n") + "\n"
    }

    private static func utf8Metadata(_ data: Data) -> [String: String] {
        guard var source = String(data: data, encoding: .utf8) else { return [:] }
        source = source.trimmingCharacters(in: CharacterSet(charactersIn: "\0\r\n"))
        return Dictionary(uniqueKeysWithValues: source.split(separator: "\n").compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<separator])
            guard ["UN", "HN", "NN", "GN"].contains(key) else { return nil }
            return (key, String(line[line.index(after: separator)...]))
        })
    }
}

public struct IPMessengerPacket: Sendable, Equatable {
    public let packetNumber: UInt64
    public let userName: String
    public let hostName: String
    public let command: UInt32
    public let additional: String
    public let groupName: String?

    public var mode: UInt32 {
        command & IPMessengerProtocol.commandMask
    }

    public var options: UInt32 {
        command & IPMessengerProtocol.optionMask
    }

    public init(
        packetNumber: UInt64,
        userName: String,
        hostName: String,
        command: UInt32,
        additional: String = "",
        groupName: String? = nil
    ) {
        self.packetNumber = packetNumber
        self.userName = userName
        self.hostName = hostName
        self.command = command
        self.additional = additional
        self.groupName = groupName
    }
}

public struct IPMessengerConfiguration: Sendable, Equatable {
    public var displayName: String
    public var groupName: String
    public var port: UInt16
    public var broadcastAddresses: [String]

    public init(
        displayName: String,
        groupName: String = "",
        port: UInt16 = IPMessengerProtocol.defaultPort,
        broadcastAddresses: [String] = ["255.255.255.255"]
    ) {
        self.displayName = displayName
        self.groupName = groupName
        self.port = port
        self.broadcastAddresses = broadcastAddresses
    }
}

public struct IPMessengerPeer: Identifiable, Sendable, Hashable {
    public let address: String
    public let port: UInt16
    public let userName: String
    public let hostName: String
    public let displayName: String
    public let groupName: String
    public let supportsUTF8: Bool
    public let lastSeen: Date

    public var id: String {
        "\(address):\(port):\(userName)"
    }

    public init(
        address: String,
        port: UInt16,
        userName: String,
        hostName: String,
        displayName: String,
        groupName: String,
        supportsUTF8: Bool,
        lastSeen: Date = Date()
    ) {
        self.address = address
        self.port = port
        self.userName = userName
        self.hostName = hostName
        self.displayName = displayName
        self.groupName = groupName
        self.supportsUTF8 = supportsUTF8
        self.lastSeen = lastSeen
    }
}

public struct IPMessengerReceivedMessage: Sendable, Equatable {
    public let packetNumber: UInt64
    public let peer: IPMessengerPeer
    public let body: String
    public let receivedAt: Date

    public init(packetNumber: UInt64, peer: IPMessengerPeer, body: String, receivedAt: Date = Date()) {
        self.packetNumber = packetNumber
        self.peer = peer
        self.body = body
        self.receivedAt = receivedAt
    }
}

public enum IPMessengerError: LocalizedError, Equatable, Sendable {
    case invalidPacket
    case invalidPort
    case invalidAddress(String)
    case messageTooLarge
    case encryptedMessageUnsupported
    case socketFailure(Int32)
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .invalidPacket: "IP Messengerパケットが不正"
        case .invalidPort: "IP Messengerのポート番号が不正"
        case let .invalidAddress(address): "ブロードキャスト先のアドレスが不正: \(address)"
        case .messageTooLarge: "IP Messengerのメッセージが大きすぎる"
        case .encryptedMessageUnsupported: "暗号化されたIP Messengerメッセージには未対応"
        case let .socketFailure(code): String(cString: strerror(code))
        case .notRunning: "IP Messengerが起動していない"
        }
    }
}

public final class IPMessengerService: @unchecked Sendable {
    public typealias PeersHandler = @MainActor @Sendable ([IPMessengerPeer]) -> Void
    public typealias MessageHandler = @MainActor @Sendable (IPMessengerReceivedMessage) -> Void
    public typealias DeliveryHandler = @MainActor @Sendable (UInt64, Bool) -> Void
    public typealias ErrorHandler = @MainActor @Sendable (Error) -> Void

    public var onPeersChange: PeersHandler?
    public var onMessage: MessageHandler?
    public var onDelivery: DeliveryHandler?
    public var onError: ErrorHandler?

    private struct PendingMessage {
        let data: Data
        let address: String
        let port: UInt16
        var attempts: Int
    }

    private let queue = DispatchQueue(label: "dev.utatane.ip-messenger")
    private let logger = Logger(subsystem: "dev.utatane.app", category: "IPMessenger")
    private var socketDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var configuration: IPMessengerConfiguration?
    private var peers: [String: IPMessengerPeer] = [:]
    private var pendingMessages: [UInt64: PendingMessage] = [:]
    private var nextPacketNumber = UInt64(Date().timeIntervalSince1970)
    private var localUserName = ""
    private var localHostName = ""

    public init() {}

    deinit {
        readSource?.cancel()
    }

    public func start(configuration: IPMessengerConfiguration) throws {
        try queue.sync {
            stopLocked(announcesExit: true)
            guard configuration.port > 0 else { throw IPMessengerError.invalidPort }
            for address in configuration.broadcastAddresses {
                try Self.validateIPv4Address(address)
            }

            let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard descriptor >= 0 else { throw IPMessengerError.socketFailure(errno) }
            do {
                let boundPort = try Self.configureSocket(descriptor, port: configuration.port)
                logger.debug("Listening on UDP port \(boundPort)")
            } catch {
                Darwin.close(descriptor)
                throw error
            }

            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.receiveAvailableDatagrams() }
            source.setCancelHandler { Darwin.close(descriptor) }
            socketDescriptor = descriptor
            readSource = source
            self.configuration = configuration
            localUserName = Self.localUserName()
            localHostName = Self.localHostName()
            peers.removeAll()
            pendingMessages.removeAll()
            source.resume()
            broadcast(mode: IPMessengerProtocol.broadcastEntry)
            publishPeers()
        }
    }

    public func stop() {
        queue.sync { stopLocked(announcesExit: true) }
    }

    public func refresh() {
        queue.async { [weak self] in
            self?.broadcast(mode: IPMessengerProtocol.broadcastEntry)
        }
    }

    public func sendMessage(_ body: String, to peer: IPMessengerPeer) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, socketDescriptor >= 0, configuration != nil else {
                    continuation.resume(throwing: IPMessengerError.notRunning)
                    return
                }
                do {
                    let packetNumber = makePacketNumber()
                    let data = try packetData(
                        mode: IPMessengerProtocol.sendMessage,
                        options: Self.messageOptions(for: peer),
                        packetNumber: packetNumber,
                        additional: body
                    )
                    try send(data, address: peer.address, port: peer.port)
                    pendingMessages[packetNumber] = PendingMessage(
                        data: data,
                        address: peer.address,
                        port: peer.port,
                        attempts: 1
                    )
                    scheduleRetry(for: packetNumber)
                    continuation.resume(returning: packetNumber)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopLocked(announcesExit: Bool) {
        guard socketDescriptor >= 0 else { return }
        if announcesExit {
            broadcast(mode: IPMessengerProtocol.broadcastExit)
        }
        let source = readSource
        readSource = nil
        socketDescriptor = -1
        configuration = nil
        peers.removeAll()
        pendingMessages.removeAll()
        source?.cancel()
        publishPeers()
    }

    private func broadcast(mode: UInt32) {
        guard let configuration else { return }
        do {
            let data = try packetData(
                mode: mode,
                options: IPMessengerProtocol.utf8CapabilityOption,
                packetNumber: makePacketNumber(),
                additional: configuration.displayName,
                groupName: configuration.groupName
            )
            var lastError: Error?
            var sent = false
            let destinations = Self.presenceAddresses(
                interfaceAddresses: Self.interfaceBroadcastAddresses(),
                configuredAddresses: configuration.broadcastAddresses
            )
            for address in destinations {
                do {
                    try send(data, address: address, port: configuration.port)
                    logger.debug("Sent presence mode \(mode) to \(address, privacy: .public):\(configuration.port)")
                    sent = true
                } catch {
                    lastError = error
                }
            }
            if !sent, let lastError {
                throw lastError
            }
        } catch {
            publish(error)
        }
    }

    private func receiveAvailableDatagrams() {
        while socketDescriptor >= 0 {
            var buffer = [UInt8](repeating: 0, count: IPMessengerProtocol.maximumDatagramBytes)
            var sourceAddress = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &sourceAddress) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    buffer.withUnsafeMutableBytes { bytes in
                        Darwin.recvfrom(
                            socketDescriptor,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            socketAddress,
                            &sourceLength
                        )
                    }
                }
            }
            if received < 0 {
                if errno != EAGAIN, errno != EWOULDBLOCK {
                    publish(IPMessengerError.socketFailure(errno))
                }
                return
            }
            guard received > 0, let address = Self.string(from: sourceAddress) else { continue }
            handle(
                Data(buffer.prefix(received)),
                address: address,
                port: UInt16(bigEndian: sourceAddress.sin_port)
            )
        }
    }

    private func handle(_ data: Data, address: String, port: UInt16) {
        do {
            let packet = try IPMessengerProtocol.decode(data)
            logger.debug("Received mode \(packet.mode) from \(address, privacy: .public):\(port)")
            if packet.userName == localUserName, packet.hostName == localHostName, port == configuration?.port {
                return
            }
            switch packet.mode {
            case IPMessengerProtocol.broadcastEntry:
                let peer = upsertPeer(from: packet, address: address, port: port)
                try sendEntryAnswer(to: peer)
            case IPMessengerProtocol.answerEntry, IPMessengerProtocol.broadcastAbsence:
                _ = upsertPeer(from: packet, address: address, port: port)
            case IPMessengerProtocol.broadcastExit:
                removePeer(packet: packet, address: address, port: port)
            case IPMessengerProtocol.sendMessage:
                guard packet.command & IPMessengerProtocol.encryptionOption == 0 else {
                    throw IPMessengerError.encryptedMessageUnsupported
                }
                let peer = upsertPeer(from: packet, address: address, port: port, usesEntryIdentity: false)
                publish(IPMessengerReceivedMessage(
                    packetNumber: packet.packetNumber,
                    peer: peer,
                    body: packet.additional
                ))
                if packet.command & IPMessengerProtocol.sendCheckOption != 0,
                   packet.command & (IPMessengerProtocol.broadcastOption | IPMessengerProtocol.autoReplyOption) == 0
                {
                    let acknowledgement = try packetData(
                        mode: IPMessengerProtocol.receiveMessage,
                        options: IPMessengerProtocol.utf8Option,
                        packetNumber: makePacketNumber(),
                        additional: String(packet.packetNumber)
                    )
                    try send(acknowledgement, address: address, port: port)
                }
            case IPMessengerProtocol.receiveMessage:
                guard let packetNumber = UInt64(packet.additional), pendingMessages.removeValue(forKey: packetNumber) != nil
                else { return }
                publishDelivery(packetNumber: packetNumber, delivered: true)
            case IPMessengerProtocol.getInfo:
                let response = try packetData(
                    mode: IPMessengerProtocol.sendInfo,
                    options: IPMessengerProtocol.utf8Option,
                    packetNumber: makePacketNumber(),
                    additional: "Utatane"
                )
                try send(response, address: address, port: port)
            default:
                break
            }
        } catch {
            publish(error)
        }
    }

    @discardableResult
    private func upsertPeer(
        from packet: IPMessengerPacket,
        address: String,
        port: UInt16,
        usesEntryIdentity: Bool = true
    ) -> IPMessengerPeer {
        let id = "\(address):\(port):\(packet.userName)"
        let peer = Self.makePeer(
            from: packet,
            address: address,
            port: port,
            existing: peers[id],
            usesEntryIdentity: usesEntryIdentity
        )
        peers[id] = peer
        publishPeers()
        return peer
    }

    static func makePeer(
        from packet: IPMessengerPacket,
        address: String,
        port: UInt16,
        existing: IPMessengerPeer?,
        usesEntryIdentity: Bool
    ) -> IPMessengerPeer {
        IPMessengerPeer(
            address: address,
            port: port,
            userName: packet.userName,
            hostName: packet.hostName,
            displayName: usesEntryIdentity
                ? (packet.additional.isEmpty ? packet.userName : packet.additional)
                : (existing?.displayName ?? packet.userName),
            groupName: usesEntryIdentity ? (packet.groupName ?? "") : (existing?.groupName ?? ""),
            supportsUTF8: existing?.supportsUTF8 == true
                || packet.command & IPMessengerProtocol.utf8CapabilityOption != 0
                || packet.command & IPMessengerProtocol.utf8Option != 0
        )
    }

    static func messageOptions(for peer: IPMessengerPeer) -> UInt32 {
        IPMessengerProtocol.sendCheckOption
            | (peer.supportsUTF8 ? IPMessengerProtocol.utf8Option : 0)
    }

    private func removePeer(packet: IPMessengerPacket, address: String, port: UInt16) {
        peers = peers.filter { _, peer in
            !(peer.address == address && peer.port == port && peer.userName == packet.userName)
        }
        publishPeers()
    }

    private func sendEntryAnswer(to peer: IPMessengerPeer) throws {
        guard let configuration else { return }
        let data = try packetData(
            mode: IPMessengerProtocol.answerEntry,
            options: IPMessengerProtocol.utf8CapabilityOption,
            packetNumber: makePacketNumber(),
            additional: configuration.displayName,
            groupName: configuration.groupName
        )
        try send(data, address: peer.address, port: peer.port)
    }

    private func packetData(
        mode: UInt32,
        options: UInt32,
        packetNumber: UInt64,
        additional: String,
        groupName: String? = nil
    ) throws -> Data {
        try IPMessengerProtocol.encode(IPMessengerPacket(
            packetNumber: packetNumber,
            userName: localUserName,
            hostName: localHostName,
            command: mode | options,
            additional: additional,
            groupName: groupName
        ))
    }

    private func send(_ data: Data, address: String, port: UInt16) throws {
        guard socketDescriptor >= 0 else { throw IPMessengerError.notRunning }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address, &destination.sin_addr) == 1 else {
            throw IPMessengerError.invalidAddress(address)
        }
        let sent = withUnsafePointer(to: &destination) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                data.withUnsafeBytes { bytes in
                    Darwin.sendto(
                        socketDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        guard sent == data.count else { throw IPMessengerError.socketFailure(errno) }
    }

    private func scheduleRetry(for packetNumber: UInt64) {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, var pending = pendingMessages[packetNumber] else { return }
            guard pending.attempts < 3 else {
                pendingMessages.removeValue(forKey: packetNumber)
                publishDelivery(packetNumber: packetNumber, delivered: false)
                return
            }
            do {
                try send(pending.data, address: pending.address, port: pending.port)
                pending.attempts += 1
                pendingMessages[packetNumber] = pending
                scheduleRetry(for: packetNumber)
            } catch {
                pendingMessages.removeValue(forKey: packetNumber)
                publishDelivery(packetNumber: packetNumber, delivered: false)
                publish(error)
            }
        }
    }

    private func makePacketNumber() -> UInt64 {
        nextPacketNumber &+= 1
        return nextPacketNumber
    }

    private func publishPeers() {
        let snapshot = peers.values.sorted {
            for (left, right) in [
                ($0.groupName, $1.groupName),
                ($0.displayName, $1.displayName),
                ($0.address, $1.address)
            ] {
                let result = left.localizedStandardCompare(right)
                if result != .orderedSame {
                    return result == .orderedAscending
                }
            }
            return false
        }
        guard let onPeersChange else { return }
        Task { @MainActor in onPeersChange(snapshot) }
    }

    private func publish(_ message: IPMessengerReceivedMessage) {
        guard let onMessage else { return }
        Task { @MainActor in onMessage(message) }
    }

    private func publishDelivery(packetNumber: UInt64, delivered: Bool) {
        guard let onDelivery else { return }
        Task { @MainActor in onDelivery(packetNumber, delivered) }
    }

    private func publish(_ error: Error) {
        guard let onError else { return }
        Task { @MainActor in onError(error) }
    }

    private static func configureSocket(_ descriptor: Int32, port: UInt16) throws -> UInt16 {
        var enabled: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_REUSEPORT, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0
        else { throw IPMessengerError.socketFailure(errno) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw IPMessengerError.socketFailure(errno)
        }
        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = port.bigEndian
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY)
        var result = withUnsafePointer(to: &localAddress) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0, errno == EADDRINUSE {
            localAddress.sin_port = 0
            result = withUnsafePointer(to: &localAddress) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard result == 0 else { throw IPMessengerError.socketFailure(errno) }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &boundAddress) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.getsockname(descriptor, socketAddress, &boundLength)
            }
        }
        guard resolved == 0 else { throw IPMessengerError.socketFailure(errno) }
        return UInt16(bigEndian: boundAddress.sin_port)
    }

    private static func validateIPv4Address(_ address: String) throws {
        var parsed = in_addr()
        guard inet_pton(AF_INET, address, &parsed) == 1 else {
            throw IPMessengerError.invalidAddress(address)
        }
    }

    static func interfaceBroadcastAddresses() -> [String] {
        var firstInterface: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstInterface) == 0, let firstInterface else { return [] }
        defer { freeifaddrs(firstInterface) }

        var result: [String] = []
        for interfacePointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = interfacePointer.pointee
            guard interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_BROADCAST) != 0,
                  let addressPointer = interface.ifa_addr,
                  let netmaskPointer = interface.ifa_netmask,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET),
                  netmaskPointer.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            let address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            let netmask = netmaskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            guard let broadcast = broadcastAddress(address: address, netmask: netmask),
                  !result.contains(broadcast)
            else { continue }
            result.append(broadcast)
        }
        return result
    }

    static func presenceAddresses(
        interfaceAddresses: [String],
        configuredAddresses: [String]
    ) -> [String] {
        var visited: Set<String> = []
        return (interfaceAddresses + ["127.0.0.1"] + configuredAddresses).filter {
            visited.insert($0).inserted
        }
    }

    static func broadcastAddress(address: in_addr, netmask: in_addr) -> String? {
        var broadcast = in_addr(s_addr: address.s_addr | ~netmask.s_addr)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &broadcast, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func string(from address: sockaddr_in) -> String? {
        var address = address.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func localUserName() -> String {
        "Utatane"
    }

    private static func localHostName() -> String {
        "Utatane-\(UUID().uuidString.prefix(8).lowercased())"
    }
}
