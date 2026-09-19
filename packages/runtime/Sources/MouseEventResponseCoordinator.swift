import Foundation
import UtataneCore

/// Applies SSP's response-dependent ordering for mouse button events.
@MainActor
public final class MouseEventResponseCoordinator {
    public typealias Request = @MainActor (GhostEvent) async -> PersonalityResponse?
    public typealias Receive = @MainActor (PersonalityResponse) -> Void

    private struct ButtonKey: Hashable {
        let scope: Int
        let button: Int
    }

    private var pendingMouseUp: [ButtonKey: Task<Bool, Never>] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public func submit(
        _ event: GhostMouseEvent,
        request: @escaping Request,
        receive: @escaping Receive
    ) {
        let key = ButtonKey(scope: event.scope, button: event.button)
        switch event.kind {
        case .up:
            pendingMouseUp[key]?.cancel()
            pendingMouseUp[key] = Task {
                guard let response = await request(.mouse(event)) else { return false }
                guard !Task.isCancelled else { return false }
                receive(response)
                return true
            }
        case .click, .doubleClick:
            let mouseUp = pendingMouseUp.removeValue(forKey: key)
            startTask {
                guard await mouseUp?.value != true else { return }
                await Self.send(event, request: request, receive: receive)
            }
        case let .multipleClick(count):
            let mouseUp = pendingMouseUp.removeValue(forKey: key)
            startTask {
                guard await mouseUp?.value != true else { return }
                if let response = await request(.mouse(event)) {
                    guard !Task.isCancelled else { return }
                    receive(response)
                    return
                }
                let fallback = GhostMouseEvent(
                    kind: count.isMultiple(of: 2) ? .doubleClick : .click,
                    scope: event.scope,
                    region: event.region,
                    x: event.x,
                    y: event.y,
                    button: event.button
                )
                await Self.send(fallback, request: request, receive: receive)
            }
        case .dragEnd:
            pendingMouseUp.removeValue(forKey: key)?.cancel()
            startTask {
                await Self.send(event, request: request, receive: receive)
            }
        default:
            startTask {
                await Self.send(event, request: request, receive: receive)
            }
        }
    }

    public func cancel() {
        pendingMouseUp.values.forEach { $0.cancel() }
        pendingMouseUp.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func startTask(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
    }

    private static func send(
        _ event: GhostMouseEvent,
        request: @escaping Request,
        receive: @escaping Receive
    ) async {
        guard let response = await request(.mouse(event)) else { return }
        guard !Task.isCancelled else { return }
        receive(response)
    }
}
