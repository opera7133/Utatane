import AppKit
import UtataneNativeSaori
import UtatanePlatformMacOS

final class NativeSaoriWindowAdapter: NativeSaoriWindowControlling, @unchecked Sendable {
    private let controller: SurfaceWindowController

    @MainActor init(controller: SurfaceWindowController) {
        self.controller = controller
    }

    func frame(scope: Int) -> NativeSaoriWindowFrame? {
        onMain { [controller] in
            controller.windowFrame(for: scope).map {
                NativeSaoriWindowFrame(
                    x: Int($0.minX),
                    y: Int($0.minY),
                    width: Int($0.width),
                    height: Int($0.height)
                )
            }
        }
    }

    func desktopSize() -> (width: Int, height: Int) {
        onMain {
            let frame = NSScreen.main?.visibleFrame ?? .zero
            return (Int(frame.width), Int(frame.height))
        }
    }

    func move(scope: Int, x: Int, speed: Int) {
        let operation = { @MainActor [controller] in
            let distance = abs(Int(controller.windowFrame(for: scope)?.minX ?? CGFloat(x)) - x)
            let duration = speed > 0 ? ((distance + speed - 1) / speed) * 10 : 0
            Task { @MainActor in
                await controller.moveSurface(
                    scope: scope,
                    x: x,
                    y: nil,
                    time: duration,
                    isAsync: false
                )
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(operation)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(operation) }
        }
    }

    private func onMain<T: Sendable>(_ operation: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(operation)
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(operation) }
    }
}
