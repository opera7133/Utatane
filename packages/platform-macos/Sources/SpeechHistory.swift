import AppKit
import Combine
import Foundation
import SwiftUI
import UtataneSakuraScript
import UtataneShell

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
    public let talkIdentifier: UUID
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
        talkIdentifier: UUID = UUID(),
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
        self.talkIdentifier = talkIdentifier
        self.ghostIdentifier = ghostIdentifier
        self.ghostName = ghostName
        self.scope = scope
        self.speakerName = speakerName
        self.surfaceID = surfaceID
        self.thumbnailPNGData = thumbnailPNGData
        self.text = text
        self.timestamp = timestamp
    }

    fileprivate func withThumbnail(_ data: Data?) -> Self {
        Self(
            id: id, talkIdentifier: talkIdentifier,
            ghostIdentifier: ghostIdentifier, ghostName: ghostName,
            scope: scope, speakerName: speakerName, surfaceID: surfaceID,
            thumbnailPNGData: data, text: text, timestamp: timestamp
        )
    }
}

@MainActor
public final class SpeechHistoryStore: ObservableObject {
    @Published public private(set) var entries: [SpeechHistoryEntry] = []
    public let capacityPerGhost: Int
    private let thumbnails = SpeechHistoryThumbnailPool()
    var uniqueThumbnailCount: Int {
        thumbnails.count
    }

    public init(capacityPerGhost: Int = 500) {
        self.capacityPerGhost = max(1, capacityPerGhost)
    }

    public func append(_ entry: SpeechHistoryEntry) {
        entries.append(entry.withThumbnail(thumbnails.retain(entry.thumbnailPNGData)))
        trimEntries(for: entry.ghostIdentifier)
    }

    public func upsert(_ entry: SpeechHistoryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let previous = entries[index].thumbnailPNGData
            if previous == entry.thumbnailPNGData {
                // Character-by-character updates keep the already shared bytes.
                entries[index] = entry.withThumbnail(previous)
            } else {
                let data = thumbnails.retain(entry.thumbnailPNGData)
                thumbnails.release(previous)
                entries[index] = entry.withThumbnail(data)
            }
        } else {
            entries.append(entry.withThumbnail(thumbnails.retain(entry.thumbnailPNGData)))
        }
        trimEntries(for: entry.ghostIdentifier)
    }

    private func trimEntries(for ghostIdentifier: String) {
        let matchingIndices = entries.indices.filter {
            entries[$0].ghostIdentifier == ghostIdentifier
        }
        let overflow = matchingIndices.count - capacityPerGhost
        if overflow > 0 {
            for index in matchingIndices.prefix(overflow).reversed() {
                thumbnails.release(entries.remove(at: index).thumbnailPNGData)
            }
        }
    }

    public func entries(for ghostIdentifier: String) -> [SpeechHistoryEntry] {
        entries.filter { $0.ghostIdentifier == ghostIdentifier }
    }

    public func clear(ghostIdentifier: String? = nil) {
        if let ghostIdentifier {
            entries.removeAll {
                guard $0.ghostIdentifier == ghostIdentifier else { return false }
                thumbnails.release($0.thumbnailPNGData)
                return true
            }
        } else {
            entries.removeAll(keepingCapacity: true)
            thumbnails.removeAll()
        }
    }
}

public struct SpeechHistoryView: View {
    @ObservedObject private var store: SpeechHistoryStore
    private let ghostIdentifier: String
    private let ghostName: String
    private let showsHeader: Bool
    private let background: Color
    private let textScale: CGFloat
    private let onClose: (() -> Void)?
    @State private var thumbnails = SpeechHistoryThumbnailCache()
    @State private var scrollTarget: SpeechHistoryScrollTarget?

    public init(
        store: SpeechHistoryStore,
        ghostIdentifier: String,
        ghostName: String,
        showsHeader: Bool = true,
        background: Color = Color(nsColor: .windowBackgroundColor),
        textScale: CGFloat = 1,
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.ghostIdentifier = ghostIdentifier
        self.ghostName = ghostName
        self.showsHeader = showsHeader
        self.background = background
        self.textScale = min(max(textScale, 0.5), 2)
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
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                SpeechHistoryRow(
                                    entry: entry,
                                    beginsTalk: index == 0
                                        || entries[index - 1].talkIdentifier != entry.talkIdentifier,
                                    endsTalk: index == entries.count - 1
                                        || entries[index + 1].talkIdentifier != entry.talkIdentifier,
                                    textScale: textScale,
                                    thumbnails: thumbnails
                                )
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    if let last = entries.last {
                        scrollTarget = SpeechHistoryScrollTarget(entry: last)
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onReceive(store.$entries) { updatedEntries in
                    guard let last = updatedEntries.last(where: {
                        $0.ghostIdentifier == ghostIdentifier
                    }) else { return }
                    let target = SpeechHistoryScrollTarget(entry: last)
                    guard target != scrollTarget else { return }
                    let animates = target.id != scrollTarget?.id
                    scrollTarget = target
                    DispatchQueue.main.async {
                        if animates {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        } else {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(background)
    }
}

private struct SpeechHistoryScrollTarget: Equatable {
    let id: UUID
    let textCount: Int

    init(entry: SpeechHistoryEntry) {
        id = entry.id
        textCount = entry.text.count
    }
}

private struct SpeechHistoryRow: View {
    let entry: SpeechHistoryEntry
    let beginsTalk: Bool
    let endsTalk: Bool
    let textScale: CGFloat
    let thumbnails: SpeechHistoryThumbnailCache

    private var accent: Color {
        let colors: [Color] = [.red, .blue, .green, .orange, .purple, .cyan]
        return colors[abs(entry.scope) % colors.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let image = thumbnails.image(for: entry.thumbnailPNGData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(.secondary.opacity(0.16))
                        Text(String(entry.speakerName.prefix(1)))
                            .font(.system(size: 13 * textScale, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.speakerName)
                        .font(.system(size: 13 * textScale, weight: .semibold))
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 10 * textScale))
                        .foregroundStyle(.secondary)
                }
                Text(entry.text)
                    .font(.system(size: 13 * textScale))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                SpeechHistoryBoundaryShape(beginsTalk: beginsTalk, endsTalk: endsTalk)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
            )
            .overlay {
                SpeechHistoryBoundaryShape(beginsTalk: beginsTalk, endsTalk: endsTalk)
                    .stroke(accent.opacity(0.9), lineWidth: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpeechHistoryBoundaryShape: Shape {
    let beginsTalk: Bool
    let endsTalk: Bool

    func path(in rect: CGRect) -> Path {
        let cut = min(10, rect.width / 4, rect.height / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: beginsTalk ? rect.minY + cut : rect.minY))
        if beginsTalk {
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        if endsTalk {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

@MainActor
public final class SpeechHistoryWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 720, height: 640)
    static let minimumContentSize = NSSize(width: 560, height: 480)
    private let store: SpeechHistoryStore
    private let frameAutosaveName: String?
    private var hostingController: NSHostingController<SpeechHistoryView>?
    private var lastContentSize: NSSize?

    public init(
        store: SpeechHistoryStore,
        frameAutosaveName: String? = "UtataneSpeechHistory"
    ) {
        self.store = store
        self.frameAutosaveName = frameAutosaveName
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(ghostIdentifier: String, ghostName: String, textScale: CGFloat = 1) {
        let window = prepareWindow(
            ghostIdentifier: ghostIdentifier,
            ghostName: ghostName,
            textScale: textScale
        )
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func prepareWindow(
        ghostIdentifier: String,
        ghostName: String,
        textScale: CGFloat = 1
    ) -> NSWindow {
        let content = SpeechHistoryView(
            store: store,
            ghostIdentifier: ghostIdentifier,
            ghostName: ghostName,
            textScale: textScale
        )
        if let window, let hostingController {
            window.title = "\(String(localized: "発話履歴")) — \(ghostName)"
            hostingController.rootView = content
            return window
        } else if let window {
            window.title = "\(String(localized: "発話履歴")) — \(ghostName)"
            let hostingController = NSHostingController(rootView: content)
            window.contentViewController = hostingController
            if let lastContentSize {
                window.setContentSize(lastContentSize)
            }
            self.hostingController = hostingController
            return window
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentMinSize = Self.minimumContentSize
            window.title = "\(String(localized: "発話履歴")) — \(ghostName)"
            window.delegate = self
            let hostingController = NSHostingController(rootView: content)
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            if let frameAutosaveName {
                window.setFrameAutosaveName(frameAutosaveName)
            }
            let contentSize = window.contentLayoutRect.size
            if contentSize.width < Self.minimumContentSize.width
                || contentSize.height < Self.minimumContentSize.height
            {
                window.setContentSize(NSSize(
                    width: max(contentSize.width, Self.minimumContentSize.width),
                    height: max(contentSize.height, Self.minimumContentSize.height)
                ))
            }
            window.center()
            self.hostingController = hostingController
            self.window = window
            return window
        }
    }
}

extension SpeechHistoryWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        // A closed NSWindowController keeps its view hierarchy alive. Detach the
        // history view so its ObservableObject subscription cannot make every
        // subsequent character rebuild a hidden, ever-growing history list.
        if let window {
            lastContentSize = window.contentLayoutRect.size
            window.contentViewController = nil
        }
        hostingController = nil
    }
}

@MainActor
public final class SpeechHistoryPresenter {
    private let store: SpeechHistoryStore
    private let context: SpeechHistoryContext
    private let presentationSession: GhostPresentationSession
    private var item: (any PresentationItem)?
    private var textScale: CGFloat

    public init(
        store: SpeechHistoryStore,
        context: SpeechHistoryContext,
        presentationSession: GhostPresentationSession,
        textScale: CGFloat = 1
    ) {
        self.store = store
        self.context = context
        self.presentationSession = presentationSession
        self.textScale = min(max(textScale, 0.5), 2)
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
            background: .clear,
            textScale: textScale,
            onClose: { [weak self] in self?.hide() }
        ))
        item.show(activating: true)
        self.item = item
        return true
    }

    public func hide() {
        guard let item else { return }
        item.hide()
        item.contentView = NSView()
    }

    public func setTextScale(_ scale: CGFloat) {
        textScale = min(max(scale, 0.5), 2)
        if isPresented {
            _ = show()
        }
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
    private static let liveUpdateCharacterStride = 8
    private let store: SpeechHistoryStore
    private let context: SpeechHistoryContext
    private let surfaceID: (Int) -> Int?
    private let thumbnailPNGData: (Int) -> Data?
    private var scope: Int
    private var text = ""
    private var mode: SakuraScriptVoiceMode = .defaultValue
    private var alternateHasVisibleContent = false
    private var entryID: UUID?
    private var timestamp: Date?
    private var entrySurfaceID: Int?
    private var entryThumbnailPNGData: Data?
    private var charactersSincePublication = 0
    private var hasPublishedCurrentEntry = false
    private let talkIdentifier = UUID()

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
            charactersSincePublication += 1
            publishIfNeeded()
        case .disabled:
            break
        case .alternate:
            let needsPublication = !alternateHasVisibleContent
            alternateHasVisibleContent = true
            markStarted()
            if needsPublication {
                publish(force: true)
            }
        }
    }

    mutating func append(_ value: String) {
        for character in value {
            append(character)
        }
    }

    mutating func appendLineBreak() {
        append(Character("\n"))
    }

    mutating func finish() {
        commit()
    }

    private mutating func markStarted() {
        guard entryID == nil else { return }
        entryID = UUID()
        timestamp = Date()
        entrySurfaceID = surfaceID(scope)
        entryThumbnailPNGData = thumbnailPNGData(scope)
    }

    private mutating func flushAlternateText() {
        guard case let .alternate(alternate) = mode, alternateHasVisibleContent else { return }
        text.append(alternate)
        alternateHasVisibleContent = false
        publish(force: true)
    }

    private mutating func commit() {
        flushAlternateText()
        publish(force: true)
        text = ""
        entryID = nil
        timestamp = nil
        entrySurfaceID = nil
        entryThumbnailPNGData = nil
        alternateHasVisibleContent = false
        charactersSincePublication = 0
        hasPublishedCurrentEntry = false
    }

    private mutating func publishIfNeeded() {
        publish(force: !hasPublishedCurrentEntry
            || charactersSincePublication >= Self.liveUpdateCharacterStride)
    }

    private mutating func publish(force: Bool) {
        guard force else { return }
        let displayedText: String = if case let .alternate(alternate) = mode, alternateHasVisibleContent {
            text + alternate
        } else {
            text
        }
        guard displayedText.contains(where: { !$0.isWhitespace }) else { return }
        markStarted()
        guard let entryID else { return }
        store.upsert(SpeechHistoryEntry(
            id: entryID,
            talkIdentifier: talkIdentifier,
            ghostIdentifier: context.ghostIdentifier,
            ghostName: context.ghostName,
            scope: scope,
            speakerName: context.speakerNames[scope] ?? context.ghostName,
            surfaceID: entrySurfaceID,
            thumbnailPNGData: entryThumbnailPNGData,
            text: displayedText,
            timestamp: timestamp ?? Date()
        ))
        charactersSincePublication = 0
        hasPublishedCurrentEntry = true
    }
}

enum SpeechHistoryThumbnail {
    static func pngData(
        from image: NSImage,
        iconRect: SurfaceRect? = nil,
        pixelSize: Int = 64
    ) -> Data? {
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
              )
        else { return nil }

        // Core Image can produce extended/float color spaces which colorAt cannot
        // interpret. Let AppKit convert and resample into the small RGBA bitmap.
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let topOriginSource = sourceRect(for: image.size, iconRect: iconRect)
        let source = NSRect(
            x: topOriginSource.minX,
            y: image.size.height - topOriginSource.maxY,
            width: topOriginSource.width,
            height: topOriginSource.height
        )
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
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
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func sourceRect(for imageSize: NSSize, iconRect: SurfaceRect?) -> NSRect {
        guard let iconRect else {
            let side = min(imageSize.width, imageSize.height)
            return NSRect(
                x: (imageSize.width - side) / 2,
                y: 0,
                width: side,
                height: side
            )
        }

        let left = CGFloat(min(iconRect.left, iconRect.right))
        let right = CGFloat(max(iconRect.left, iconRect.right))
        let top = CGFloat(min(iconRect.top, iconRect.bottom))
        let bottom = CGFloat(max(iconRect.top, iconRect.bottom))
        let side = max(1, max(right - left, bottom - top))
        let centerX = (left + right) / 2
        let centerYFromTop = (top + bottom) / 2
        return NSRect(
            x: centerX - side / 2,
            y: centerYFromTop - side / 2,
            width: side,
            height: side
        )
    }
}
