import AppKit
import SwiftUI
import UtataneNetwork

@MainActor
final class IPMessengerWindowController: NSWindowController, ObservableObject {
    struct ConversationMessage: Identifiable {
        enum Direction: Equatable {
            case incoming
            case outgoing
        }

        enum Delivery: Equatable {
            case received
            case sending
            case delivered
            case failed
        }

        let id = UUID()
        let peerID: String
        let direction: Direction
        let body: String
        let date: Date
        var packetNumber: UInt64?
        var delivery: Delivery
    }

    @Published private(set) var peers: [IPMessengerPeer] = []
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var isRunning = false
    @Published private(set) var statusText: String?
    @Published var selectedPeerID: String?
    @Published var draft = ""

    var onOpenSettings: (() -> Void)?
    var onReceiveMessage: ((IPMessengerReceivedMessage) -> Void)?

    private let service = IPMessengerService()
    private var activeConfiguration: IPMessengerConfiguration?

    override init(window: NSWindow? = nil) {
        super.init(window: window)
        service.onPeersChange = { [weak self] peers in
            guard let self else { return }
            self.peers = peers
            if let selectedPeerID, !peers.contains(where: { $0.id == selectedPeerID }) {
                self.selectedPeerID = nil
            }
            if selectedPeerID == nil {
                selectedPeerID = peers.first?.id
            }
        }
        service.onMessage = { [weak self] message in
            self?.receive(message)
        }
        service.onDelivery = { [weak self] packetNumber, delivered in
            self?.updateDelivery(packetNumber: packetNumber, delivered: delivered)
        }
        service.onError = { [weak self] error in
            self?.statusText = error.localizedDescription
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(enabled: Bool, configuration: IPMessengerConfiguration) {
        if !enabled {
            service.stop()
            activeConfiguration = nil
            isRunning = false
            peers = []
            statusText = nil
            return
        }
        guard !isRunning || activeConfiguration != configuration else { return }
        do {
            try service.start(configuration: configuration)
            activeConfiguration = configuration
            isRunning = true
            statusText = nil
        } catch {
            activeConfiguration = nil
            isRunning = false
            statusText = error.localizedDescription
        }
    }

    func showMessenger() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: IPMessengerView(controller: self)))
            window.title = String(localized: "IP Messenger")
            window.setContentSize(NSSize(width: 840, height: 560))
            window.minSize = NSSize(width: 680, height: 460)
            window.styleMask.insert([.resizable, .closable, .miniaturizable, .titled])
            window.isReleasedWhenClosed = false
            self.window = window
        }
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func refresh() {
        guard isRunning else {
            statusText = String(localized: "本体設定でIP Messengerを有効にして。")
            return
        }
        statusText = nil
        service.refresh()
    }

    func sendDraft() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let peer = selectedPeer else { return }
        draft = ""
        Task {
            do {
                let packetNumber = try await service.sendMessage(body, to: peer)
                messages.append(ConversationMessage(
                    peerID: peer.id,
                    direction: .outgoing,
                    body: body,
                    date: Date(),
                    packetNumber: packetNumber,
                    delivery: .sending
                ))
                statusText = nil
            } catch {
                draft = body
                statusText = error.localizedDescription
            }
        }
    }

    func clearConversation() {
        guard let selectedPeerID else { return }
        messages.removeAll { $0.peerID == selectedPeerID }
    }

    func stop() {
        service.stop()
        isRunning = false
        activeConfiguration = nil
        peers = []
    }

    var selectedPeer: IPMessengerPeer? {
        guard let selectedPeerID else { return nil }
        return peers.first { $0.id == selectedPeerID }
    }

    var selectedMessages: [ConversationMessage] {
        guard let selectedPeerID else { return [] }
        return messages.filter { $0.peerID == selectedPeerID }
    }

    private func receive(_ message: IPMessengerReceivedMessage) {
        if !peers.contains(where: { $0.id == message.peer.id }) {
            peers.append(message.peer)
        }
        selectedPeerID = message.peer.id
        messages.append(ConversationMessage(
            peerID: message.peer.id,
            direction: .incoming,
            body: message.body,
            date: message.receivedAt,
            packetNumber: message.packetNumber,
            delivery: .received
        ))
        onReceiveMessage?(message)
        showMessenger()
        NSApplication.shared.requestUserAttention(.informationalRequest)
    }

    private func updateDelivery(packetNumber: UInt64, delivered: Bool) {
        guard let index = messages.lastIndex(where: { $0.packetNumber == packetNumber }) else { return }
        messages[index].delivery = delivered ? .delivered : .failed
    }
}

private struct IPMessengerView: View {
    @ObservedObject var controller: IPMessengerWindowController

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("メンバー")
                        .font(.headline)
                    Spacer()
                    Button {
                        controller.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("メンバーを更新")
                }
                .padding(12)

                Divider()

                if controller.peers.isEmpty {
                    ContentUnavailableView(
                        "メンバーが見つかりません",
                        systemImage: "person.2.slash",
                        description: Text(controller.isRunning
                            ? "同じLANのIP Messengerを更新して。"
                            : "本体設定でIP Messengerを有効にして。")
                    )
                } else {
                    List(controller.peers, selection: $controller.selectedPeerID) { peer in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peer.displayName)
                                .fontWeight(.medium)
                            Text(peerSubtitle(peer))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(peer.id)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)

            conversation
                .frame(minWidth: 440)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("設定…") { controller.onOpenSettings?() }
                Button("履歴を消去") { controller.clearConversation() }
                    .disabled(controller.selectedMessages.isEmpty)
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.selectedPeer?.displayName ?? String(localized: "送信先を選択"))
                        .font(.headline)
                    if let peer = controller.selectedPeer {
                        Text("\(peer.address):\(peer.port) · \(peer.hostName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Label(
                    controller.isRunning ? "受信中" : "停止中",
                    systemImage: controller.isRunning ? "circle.fill" : "circle"
                )
                .font(.caption)
                .foregroundStyle(controller.isRunning ? .green : .secondary)
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if controller.selectedMessages.isEmpty {
                            ContentUnavailableView(
                                "メッセージはありません",
                                systemImage: "bubble.left.and.bubble.right"
                            )
                            .padding(.top, 60)
                        } else {
                            ForEach(controller.selectedMessages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: controller.selectedMessages.count) { _, _ in
                    if let last = controller.selectedMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            if let statusText = controller.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $controller.draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 70, maxHeight: 120)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator)
                    }
                Button {
                    controller.sendDraft()
                } label: {
                    Label("送信", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(
                    !controller.isRunning
                        || controller.selectedPeer == nil
                        || controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding(12)
        }
    }

    private func messageRow(_ message: IPMessengerWindowController.ConversationMessage) -> some View {
        HStack {
            if message.direction == .outgoing {
                Spacer(minLength: 80)
            }
            VStack(alignment: message.direction == .outgoing ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        message.direction == .outgoing ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                HStack(spacing: 5) {
                    Text(message.date, style: .time)
                    if message.direction == .outgoing {
                        Text(deliveryLabel(message.delivery))
                    }
                }
                .font(.caption2)
                .foregroundStyle(message.delivery == .failed ? .red : .secondary)
            }
            if message.direction == .incoming {
                Spacer(minLength: 80)
            }
        }
    }

    private func peerSubtitle(_ peer: IPMessengerPeer) -> String {
        let identity = "\(peer.userName)@\(peer.hostName)"
        return peer.groupName.isEmpty ? identity : "\(peer.groupName) · \(identity)"
    }

    private func deliveryLabel(_ delivery: IPMessengerWindowController.ConversationMessage.Delivery) -> String {
        switch delivery {
        case .received: ""
        case .sending: String(localized: "確認待ち")
        case .delivered: String(localized: "配信済み")
        case .failed: String(localized: "未確認")
        }
    }
}
