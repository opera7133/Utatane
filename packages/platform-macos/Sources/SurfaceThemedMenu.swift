import AppKit

@MainActor
final class SurfaceThemedMenuController {
    static let shared = SurfaceThemedMenuController()
    private(set) var panels: [SurfaceMenuPanel] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?

    func show(items: [SurfaceContextMenuItem], appearance: SurfaceMenuAppearance, at point: NSPoint) {
        close()
        open(items: items, appearance: appearance, at: point, level: 0)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.panels.contains(where: { $0 === event.window }) {
                    self.close()
                }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        close(after: -1)
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let deactivationObserver {
            NotificationCenter.default.removeObserver(deactivationObserver)
        }
        localMonitor = nil; globalMonitor = nil; deactivationObserver = nil
    }

    func close(after level: Int) {
        for panel in panels.dropFirst(level + 1) {
            panel.orderOut(nil); panel.close()
        }
        panels = Array(panels.prefix(level + 1))
    }

    func open(items: [SurfaceContextMenuItem], appearance: SurfaceMenuAppearance, at point: NSPoint, level: Int) {
        close(after: level - 1)
        guard !items.isEmpty else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let view = SurfaceThemedMenuView(items: items, appearance: appearance, controller: self, level: level)
        let width = min(view.frame.width, visible.width - 8)
        let height = min(view.frame.height, visible.height - 8)
        var x = point.x
        if level > 0, x + width > visible.maxX, let parent = panels.last {
            x = parent.frame.minX - width
        }
        let origin = NSPoint(x: min(max(x, visible.minX + 4), visible.maxX - width - 4),
                             y: min(max(point.y - height, visible.minY + 4), visible.maxY - height - 4))
        let panel = SurfaceMenuPanel(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.menuView = view
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = view.frame.height > height
        scroll.autohidesScrollers = true
        view.frame.size.width = width
        scroll.documentView = view
        panel.contentView = scroll
        panels.append(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func select(_ item: SurfaceContextMenuItem, index: Int, view: SurfaceThemedMenuView) {
        switch item {
        case let .action(_, _, enabled, handler) where enabled:
            close()
            handler()
        case let .submenu(_, items):
            guard let window = view.window else { return }
            let row = view.rowRect(index)
            let converted = window.convertToScreen(view.convert(row, to: nil))
            open(items: items, appearance: view.menuAppearance, at: NSPoint(x: window.frame.maxX, y: converted.maxY), level: view.level + 1)
        default: break
        }
    }
}

@MainActor
final class SurfaceMenuPanel: NSPanel {
    weak var menuView: SurfaceThemedMenuView?
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class SurfaceThemedMenuView: NSView {
    let items: [SurfaceContextMenuItem]
    let menuAppearance: SurfaceMenuAppearance
    let level: Int
    private weak var controller: SurfaceThemedMenuController?
    private(set) var selectedIndex: Int?
    private var rows: [SurfaceMenuRow] = []
    private var rowRects: [NSRect] = []
    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    init(items: [SurfaceContextMenuItem], appearance: SurfaceMenuAppearance, controller: SurfaceThemedMenuController, level: Int) {
        self.items = items; menuAppearance = appearance; self.controller = controller; self.level = level
        var width: CGFloat = 180
        var height: CGFloat = 4
        for item in items {
            let text: String = switch item {
            case let .action(title, _, _, _), let .submenu(title, _): title
            case .separator: ""
            }
            width = max(width, (text as NSString).size(withAttributes: [.font: appearance.font]).width + appearance.sidebarWidth + 64)
            let rowHeight: CGFloat = if case .separator = item {
                9
            } else {
                appearance.rowHeight
            }
            rowRects.append(NSRect(x: 0, y: height, width: width, height: rowHeight))
            height += rowHeight
        }
        super.init(frame: NSRect(x: 0, y: 0, width: min(width, 720), height: height + 4))
        setAccessibilityElement(false)
        setAccessibilityRole(.menu)
        for (index, item) in items.enumerated() {
            if case .separator = item {
                continue
            }
            let row = SurfaceMenuRow(menu: self, index: index)
            addSubview(row)
            rows.append(row)
        }
        layoutRows()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize); layoutRows()
    }

    private func layoutRows() {
        for row in rows {
            row.frame = rowRect(row.index)
        }
    }

    func rowRect(_ index: Int) -> NSRect {
        var rect = rowRects[index]; rect.size.width = bounds.width; return rect
    }

    override func draw(_ dirtyRect: NSRect) {
        menuAppearance.drawBackground(in: bounds)
        menuAppearance.frameColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        for (index, item) in items.enumerated() {
            guard case .separator = item else { continue }
            let rect = rowRect(index)
            menuAppearance.separatorColor.setFill()
            NSRect(x: menuAppearance.sidebarWidth + 8, y: rect.midY, width: max(0, bounds.width - menuAppearance.sidebarWidth - 16), height: 1).fill()
        }
    }

    func highlight(_ index: Int, openSubmenu: Bool) {
        guard isEnabled(index) else {
            selectedIndex = nil
            controller?.close(after: level)
            for row in rows {
                row.needsDisplay = true
            }
            return
        }
        if selectedIndex != index {
            controller?.close(after: level); window?.makeKey()
        }
        selectedIndex = index
        for row in rows {
            row.needsDisplay = true
        }
        if openSubmenu, case .submenu = items[index] {
            controller?.select(items[index], index: index, view: self)
        }
    }

    private func isEnabled(_ index: Int) -> Bool {
        switch items[index] {
        case let .action(_, _, enabled, _): enabled
        case let .submenu(_, items): !items.isEmpty
        case .separator: false
        }
    }

    func activate(_ index: Int) {
        guard isEnabled(index) else { return }
        controller?.select(items[index], index: index, view: self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.close()
        case 123:
            if level > 0 {
                controller?.close(after: level - 1); controller?.panels.last?.makeKey()
            }
        case 124:
            if let selectedIndex, case .submenu = items[selectedIndex] {
                activate(selectedIndex)
            }
        case 36, 76:
            if let selectedIndex {
                activate(selectedIndex)
            } else {
                move(1)
            }
        case 125: move(1)
        case 126: move(-1)
        default:
            guard let text = event.charactersIgnoringModifiers, !text.isEmpty else { return }
            let start = selectedIndex.map { $0 + 1 } ?? 0
            for offset in 0 ..< items.count {
                let index = (start + offset) % items.count
                guard isEnabled(index) else { continue }
                let title: String
                switch items[index] {
                case let .action(value, _, _, _), let .submenu(value, _): title = value
                case .separator: continue
                }
                if title.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
                    highlight(index, openSubmenu: false); scrollToSelection(); break
                }
            }
        }
    }

    func move(_ step: Int) {
        guard !items.isEmpty else { return }
        let start = selectedIndex ?? (step > 0 ? -1 : items.count)
        for offset in 1 ... items.count {
            let index = (start + step * offset + items.count * 2) % items.count
            if isEnabled(index) {
                highlight(index, openSubmenu: false); scrollToSelection(); return
            }
        }
    }

    private func scrollToSelection() {
        guard let selectedIndex else { return }
        scrollToVisible(rowRect(selectedIndex))
        if let row = rows.first(where: { $0.index == selectedIndex }) {
            NSAccessibility.post(element: row, notification: .focusedUIElementChanged)
        }
    }
}

@MainActor
private final class SurfaceMenuRow: NSButton {
    weak var ownerMenu: SurfaceThemedMenuView?
    let index: Int
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    init(menu: SurfaceThemedMenuView, index: Int) {
        ownerMenu = menu; self.index = index
        super.init(frame: .zero)
        isBordered = false
        target = self; action = #selector(invoke)
        switch menu.items[index] {
        case let .action(title, checked, enabled, _):
            self.title = title; isEnabled = enabled; state = checked ? .on : .off
        case let .submenu(title, items): self.title = title; isEnabled = !items.isEmpty
        case .separator: break
        }
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
        setAccessibilityValue(state == .on ? "1" : "0")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next); tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        ownerMenu?.highlight(index, openSubmenu: true)
    }

    @objc private func invoke() {
        ownerMenu?.activate(index)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let menu = ownerMenu else { return }
        let style = menu.menuAppearance
        let selected = menu.selectedIndex == index && isEnabled
        if selected {
            NSGraphicsContext.saveGraphicsState()
            let row = menu.rowRect(index)
            NSAffineTransform(transform: AffineTransform(translationByX: 0, byY: -row.minY)).concat()
            style.drawSelection(in: row, bounds: menu.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        let color = !isEnabled ? style.disabledTextColor : (selected ? style.selectedTextColor : style.textColor)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: color, .paragraphStyle: paragraph]
        let y = (bounds.height - style.rowHeight + 10) / 2
        (title as NSString).draw(in: NSRect(x: style.sidebarWidth + 26, y: y, width: max(0, bounds.width - style.sidebarWidth - 52), height: bounds.height), withAttributes: attributes)
        if state == .on {
            ("✓" as NSString).draw(at: NSPoint(x: style.sidebarWidth + 8, y: y), withAttributes: attributes)
        }
        if case .submenu = menu.items[index] {
            ("›" as NSString).draw(at: NSPoint(x: bounds.width - 20, y: y), withAttributes: attributes)
        }
    }
}
