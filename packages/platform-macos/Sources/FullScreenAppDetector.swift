import AppKit

@MainActor
public struct FullScreenAppDetector {
    public init() {}

    public func frontmostApplicationHasFullScreenWindow() -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windowInfo = CGWindowListCopyWindowInfo(
                  .optionOnScreenOnly, kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }
        let bounds = windowInfo.compactMap { entry -> CGRect? in
            guard (entry[kCGWindowOwnerPID as String] as? Int) == Int(application.processIdentifier),
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = entry[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: dictionary)
        }
        return fullScreenWindowExists(
            windowBounds: bounds,
            screenSizes: NSScreen.screens.map(\.frame.size)
        )
    }
}

func fullScreenWindowExists(windowBounds: [CGRect], screenSizes: [CGSize]) -> Bool {
    windowBounds.contains { window in
        screenSizes.contains { screen in
            abs(window.width - screen.width) < 2 && abs(window.height - screen.height) < 2
        }
    }
}
