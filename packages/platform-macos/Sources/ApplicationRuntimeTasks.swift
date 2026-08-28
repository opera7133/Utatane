import SwiftUI

/// Owns runtime work independently of SwiftUI visibility and task cancellation.
@MainActor
public final class ApplicationRuntimeTasks {
    private struct Entry {
        let revision: AnyHashable
        let task: Task<Void, Never>
    }

    private var entries: [String: Entry] = [:]
    private var isStopped = false

    public init() {}

    public func update(
        key: String,
        revision: some Hashable,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard !isStopped else { return }
        let revision = AnyHashable(revision)
        guard entries[key]?.revision != revision else { return }
        entries[key]?.task.cancel()
        // An unstructured task is intentionally not a child of a View's task.
        entries[key] = Entry(revision: revision, task: Task { await operation() })
    }

    public func stop() {
        isStopped = true
        for entry in entries.values {
            entry.task.cancel()
        }
        entries.removeAll()
    }
}

public extension View {
    /// Register on appearance or configuration changes, but never cancel on disappearance.
    func applicationRuntimeTask(
        in owner: ApplicationRuntimeTasks,
        key: String,
        id: some Hashable = 0,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        onChange(of: id, initial: true) { _, revision in
            owner.update(key: key, revision: revision, operation: operation)
        }
    }
}
