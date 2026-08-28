import AppKit
import Combine

/// Wait for normal termination (including ghost saves) before opening this exact bundle.
@MainActor
public final class ApplicationRelauncher: ObservableObject {
    public static let shared = ApplicationRelauncher()
    @Published public private(set) var isRestarting = false
    private var helper: Process?

    public func restart() throws {
        guard !isRestarting else { return }
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path)
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Self.makeHelper(
            applicationURL: bundle.bundleURL,
            waitingFor: ProcessInfo.processInfo.processIdentifier,
            environment: ProcessInfo.processInfo.environment
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        helper = process
        isRestarting = true
        // terminateLater enters a nested run loop. Calling it from a MainActor /
        // main-queue job would hold that executor while shutdown awaits more jobs.
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// A separate process survives the app's exit. Paths and environment values are
    /// positional arguments, never shell source. A failed/cancelled shutdown times out
    /// without opening a second copy of the ghost's writable state.
    static func makeHelper(
        applicationURL: URL,
        waitingFor processIdentifier: Int32,
        environment: [String: String] = [:],
        openExecutable: URL = URL(filePath: "/usr/bin/open"),
        attempts: Int = 3000
    ) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c", #"""
            parent_pid="$1"
            remaining="$2"
            shift 2
            while /bin/kill -0 "$parent_pid" 2>/dev/null; do
                [ "$remaining" -gt 0 ] || exit 1
                remaining=$((remaining - 1))
                /bin/sleep 0.1
            done
            exec "$@"
            """#,
            "utatane-relaunch", String(processIdentifier), String(attempts),
            openExecutable.path, "-n", "-a", applicationURL.path
        ]
        // Keep explicit development content/engine overrides, but do not propagate
        // debugger injection or launch arguments such as -AppleLanguages.
        for key in [
            "UTATANE_CONTENT_ROOT", "UTATANE_DIALOGUE_PATH", "UTATANE_GHOSTS_ROOT",
            "UTATANE_BALLOONS_ROOT", "UTATANE_HEADLINES_ROOT", "UTATANE_PLUGINS_ROOT",
            "UTATANE_WINE_EXECUTABLE", "UTATANE_WINE_PREFIX", "UTATANE_MATERIA_HOST",
            "UTATANE_MATERIA_EXE", "UTATANE_WINDOWS_DLL_HOST"
        ] {
            if let value = environment[key] {
                process.arguments?.append(contentsOf: ["--env", "\(key)=\(value)"])
            }
        }
        return process
    }
}
