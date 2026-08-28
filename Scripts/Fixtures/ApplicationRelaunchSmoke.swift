import AppKit

@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    let root = URL(filePath: ProcessInfo.processInfo.environment["UTATANE_CONTENT_ROOT"]!)
    var firstLaunch = false
    var terminating = false
    func record(_ text: String) {
        let path = root.appending(path: "events.log")
        let line = "\(Date().timeIntervalSince1970) pid=\(ProcessInfo.processInfo.processIdentifier) \(text)\n"
        let data = (try? Data(contentsOf: path)) ?? Data()
        try! (data + Data(line.utf8)).write(to: path)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let marker = root.appending(path: "first-launch")
        firstLaunch = !FileManager.default.fileExists(atPath: marker.path)
        record("launch bundle=\(Bundle.main.bundlePath) localized=\(Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil))")
        if firstLaunch {
            try! Data().write(to: marker)
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                do { try ApplicationRelauncher.shared.restart() }
                catch { self.record("ERROR \(error)"); NSApp.terminate(nil) }
            }
        } else {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        guard firstLaunch else { return .terminateNow }
        if !terminating {
            terminating = true
            record("shutdown-start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.record("shutdown-saved")
                app.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        record("will-terminate")
    }
}

@main
struct Smoke {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = SmokeDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
