import AppKit
import Combine
import Foundation
import SwiftUI
import UtataneSakuraScript

public struct SpeechHistoryContext: Sendable, Equatable {
    public var ghostIdentifier: String
    public var ghostName: String
    public var speakerNames: [Int: String]

    public init(
        ghostIdentifier: String,
        ghostName: String,
        speakerNames: [Int: String] = [:]
    ) {
        self.ghostIdentifier = ghostIdentifier
        self.ghostName = ghostName
        self.speakerNames = speakerNames
    }
}

public struct SpeechHistoryEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let ghostIdentifier: String
    public let ghostName: String
    public let scope: Int
    public let speakerName: String
    public let surfaceID: Int?
    public let thumbnailPNGData: Data?
    public let text: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        ghostIdentifier: String,
        ghostName: String,
        scope: Int,
        speakerName: String,
        surfaceID: Int?,
        thumbnailPNGData: Data? = nil,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.ghostIdentifier = ghostIdentifier
        self.ghostName = ghostName
        self.scope = scope
        self.speakerName = speakerName
        self.surfaceID = surfaceID
        self.thumbnailPNGData = thumbnailPNGData
        self.text = text
        self.timestamp = timestamp
    }
}

@MainActor
public final class SpeechHistoryStore: ObservableObject {
    @Published public private(set) var entries: [SpeechHistoryEntry] = []
    public let capacityPerGhost: Int

    public init(capacityPerGhost: Int = 500) {
        self.capacityPerGhost = max(1, capacityPerGhost)
    }

    public func append(_ entry: SpeechHistoryEntry) {
        entries.append(entry)
        let matchingIndices = entries.indices.filter {
            entries[$0].ghostIdentifier == entry.ghostIdentifier
        }
        let overflow = matchingIndices.count - capacityPerGhost
        if overflow > 0 {
            for index in matchingIndices.prefix(overflow).reversed() {
                entries.remove(at: index)
            }
        }
    }

    public func entries(for ghostIdentifier: String) -> [SpeechHistoryEntry] {
        entries.filter { $0.ghostIdentifier == ghostIdentifier }
    }

    public func clear(ghostIdentifier: String? = nil) {
        if let ghostIdentifier {
            entries.removeAll { $0.ghostIdentifier == ghostIdentifier }
        } else {
            entries.removeAll(keepingCapacity: true)
        }
    }
}

public struct SpeechHistoryView: View {
    @ObservedObject private var store: SpeechHistoryStore
    private let ghostIdentifier: String
    private let ghostName: String
    private let showsHeader: Bool
    private let background: Color
    private let onClose: (() -> Void)?

    public init(
        store: SpeechHistoryStore,
        ghostIdentifier: String,
        ghostName: String,
        showsHeader: Bool = true,
        background: Color = Color(nsColor: .windowBackgroundColor),
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.ghostIdentifier = ghostIdentifier
        self.ghostName = ghostName
        self.showsHeader = showsHeader
        self.background = background
        self.onClose = onClose
    }

    private var entries: [SpeechHistoryEntry] {
        store.entries(for: ghostIdentifier)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Text(ghostName)
                        .font(.headline)
                    Spacer()
                    Button(String(localized: "履歴を消去"), role: .destructive) {
                        store.clear(ghostIdentifier: ghostIdentifier)
                    }
                    .disabled(entries.isEmpty)
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "閉じる"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if entries.isEmpty {
                            ContentUnavailableView(
                                String(localized: "発話履歴はまだありません"),
                                systemImage: "text.bubble"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                        } else {
                            ForEach(entries) { entry in
                                SpeechHistoryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    if let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onReceive(store.$entries) { _ in
                    guard let last = entries.last else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(background)
    }
}

private struct SpeechHistoryRow: View {
    let entry: SpeechHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let thumbnailPNGData = entry.thumbnailPNGData,
                   let image = NSImage(data: thumbnailPNGData)
                {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(.secondary.opacity(0.16))
                        Text(String(entry.speakerName.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.speakerName)
                        .font(.headline)
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
public final class SpeechHistoryWindowController: NSWindowController {
    private let store: SpeechHistoryStore

    public init(store: SpeechHistoryStore) {
        self.store = store
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(ghostIdentifier: String, ghostName: String) {
        let content = SpeechHistoryView(
            store: store,
            ghostIdentifier: ghostIdentifier,
            ghostName: ghostName
        )
        if let window {
            window.title = "\(String(localized: "発話履歴")) — \(ghostName)"
            window.contentViewController = NSHostingController(rootView: content)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "\(String(localized: "発話履歴")) — \(ghostName)"
            window.contentViewController = NSHostingController(rootView: content)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("UtataneSpeechHistory")
            window.center()
            self.window = window
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
public final class SpeechHistoryPresenter {
    private let store: SpeechHistoryStore
    private let context: SpeechHistoryContext
    private let presentationSession: GhostPresentationSession
    private var item: (any PresentationItem)?

    public init(
        store: SpeechHistoryStore,
        context: SpeechHistoryContext,
        presentationSession: GhostPresentationSession
    ) {
        self.store = store
        self.context = context
        self.presentationSession = presentationSession
    }

    public var isPresented: Bool {
        item?.isVisible ?? false
    }

    @discardableResult
    public func show() -> Bool {
        guard presentationSession.geometryProvider.coordinateSpace != .desktop else { return false }
        let item = item ?? makeItem()
        item.contentView = NSHostingView(rootView: SpeechHistoryView(
            store: store,
            ghostIdentifier: context.ghostIdentifier,
            ghostName: context.ghostName,
            background: Color(nsColor: .windowBackgroundColor).opacity(0.92),
            onClose: { [weak self] in self?.hide() }
        ))
        item.show(activating: true)
        self.item = item
        return true
    }

    public func hide() {
        item?.hide()
    }

    public func discard() {
        item?.discard()
        item = nil
    }

    private func makeItem() -> any PresentationItem {
        let item = presentationSession.presentationHost.makeItem(
            kind: .speechHistory,
            title: "\(String(localized: "発話履歴")) — \(context.ghostName)",
            onMove: { _, _ in },
            onCancel: nil
        )
        item.setContentSize(NSSize(width: 380, height: 508))
        return item
    }
}

@MainActor
struct SpeechHistoryRecorder {
    private let store: SpeechHistoryStore
    private let context: SpeechHistoryContext
    private let surfaceID: (Int) -> Int?
    private let thumbnailPNGData: (Int) -> Data?
    private var scope: Int
    private var text = ""
    private var mode: SakuraScriptVoiceMode = .defaultValue
    private var alternateHasVisibleContent = false
    private var timestamp: Date?

    init(
        store: SpeechHistoryStore,
        context: SpeechHistoryContext,
        initialScope: Int,
        surfaceID: @escaping (Int) -> Int?,
        thumbnailPNGData: @escaping (Int) -> Data? = { _ in nil }
    ) {
        self.store = store
        self.context = context
        scope = initialScope
        self.surfaceID = surfaceID
        self.thumbnailPNGData = thumbnailPNGData
    }

    mutating func setScope(_ newScope: Int) {
        guard newScope != scope else { return }
        commit()
        scope = newScope
    }

    mutating func setMode(_ newMode: SakuraScriptVoiceMode) {
        flushAlternateText()
        mode = newMode
    }

    mutating func append(_ character: Character) {
        switch mode {
        case .defaultValue:
            markStarted()
            text.append(character)
        case .disabled:
            break
        case .alternate:
            alternateHasVisibleContent = true
            markStarted()
        }
    }

    mutating func appendLineBreak() {
        append("\n")
    }

    mutating func finish() {
        commit()
    }

    private mutating func markStarted() {
        if timestamp == nil {
            timestamp = Date()
        }
    }

    private mutating func flushAlternateText() {
        guard case let .alternate(alternate) = mode, alternateHasVisibleContent else { return }
        text.append(alternate)
        alternateHasVisibleContent = false
    }

    private mutating func commit() {
        flushAlternateText()
        defer {
            text = ""
            timestamp = nil
            alternateHasVisibleContent = false
        }
        guard text.contains(where: { !$0.isWhitespace }) else { return }
        store.append(SpeechHistoryEntry(
            ghostIdentifier: context.ghostIdentifier,
            ghostName: context.ghostName,
            scope: scope,
            speakerName: context.speakerNames[scope] ?? context.ghostName,
            surfaceID: surfaceID(scope),
            thumbnailPNGData: thumbnailPNGData(scope),
            text: text,
            timestamp: timestamp ?? Date()
        ))
    }
}

enum SpeechHistoryThumbnail {
    static func pngData(from image: NSImage, pixelSize: Int = 64) -> Data? {
        guard pixelSize > 0, image.size.width > 0, image.size.height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelSize,
                  pixelsHigh: pixelSize,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: pixelSize * 4,
                  bitsPerPixel: 32
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }

        let side = min(image.size.width, image.size.height)
        let source = NSRect(
            x: (image.size.width - side) / 2,
            y: image.size.height - side,
            width: side,
            height: side
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: source,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
