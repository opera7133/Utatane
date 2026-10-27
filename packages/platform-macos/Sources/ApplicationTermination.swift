import AppKit

/// Enter AppKit's terminateLater run loop without retaining a Swift executor job.
@MainActor
public enum ApplicationTermination {
    private static var isPending = false

    public static func request() {
        request { NSApplication.shared.terminate(nil) }
    }

    static func request(_ terminate: @escaping @MainActor () -> Void) {
        guard !isPending else { return }
        isPending = true
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                defer { isPending = false }
                terminate()
            }
        }
    }
}
