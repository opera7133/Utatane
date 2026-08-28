import AppKit

/// Keeps the runtime's hosting view and State storage alive when the user closes its UI.
@MainActor
public final class RuntimeHostWindowLifetime: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private nonisolated let delegateReference = WindowDelegateReference()
    private var onClose: (() -> Void)?

    public func attach(to window: NSWindow, onClose: @escaping () -> Void) {
        self.onClose = onClose
        if self.window !== window || window.delegate !== self {
            delegateReference.set(window.delegate)
            self.window = window
            window.isReleasedWhenClosed = false
            window.delegate = self
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        sender.orderOut(nil)
        return false
    }

    /// Preserve SwiftUI's other window delegate callbacks.
    override public func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) {
            return true
        }
        return delegateReference.get()?.responds(to: selector) ?? false
    }

    override public func forwardingTarget(for selector: Selector!) -> Any? {
        if let delegate = delegateReference.get(), delegate.responds(to: selector) {
            return delegate
        }
        return super.forwardingTarget(for: selector)
    }
}

/// NSObject's forwarding queries are nonisolated. Protect the weak reference even
/// though attaching the window and its actual delegate callbacks are main-actor work.
private final class WindowDelegateReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var delegate: (any NSWindowDelegate)?

    func set(_ delegate: (any NSWindowDelegate)?) {
        lock.withLock { self.delegate = delegate }
    }

    func get() -> (any NSWindowDelegate)? {
        lock.withLock { delegate }
    }
}
