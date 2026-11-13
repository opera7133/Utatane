import AppKit

struct OsuwariPlacement {
    private enum Corner: String { case tl, tr, bl, br }
    private enum Side: String { case center, top, bottom, left, right }

    private var target = "active"
    private var corner = Corner.tl
    private var side = Side.center
    private var usesWorkArea = false
    private var skipsClipping = false
    private var offset = CGPoint.zero
    private var margins = NSEdgeInsets()
    private(set) var interval = 100

    init(options: [String]) {
        for option in options {
            let fields = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = fields.first?.lowercased() else { continue }
            let value = fields.count == 2 ? String(fields[1]) : "true"
            switch name {
            case "--target":
                if ["active", "fix"].contains(value.lowercased()) || (value.hasPrefix("@") && value.count > 1) {
                    target = value
                }
            case "--origin": corner = Corner(rawValue: value.lowercased()) ?? corner
            case "--side": side = Side(rawValue: value.lowercased()) ?? side
            case "--area": usesWorkArea = value.lowercased() == "workarea"
            case "--noclip": skipsClipping = ["true", "on", "1"].contains(value.lowercased())
            case "--x": if let number = Int32(value) {
                    offset.x = CGFloat(number)
                }
            case "--y": if let number = Int32(value) {
                    offset.y = -CGFloat(number)
                }
            case "--interval": if let number = Int(value) {
                    interval = max(10, number)
                }
            case "--margin":
                let values = value.split { $0 == "_" || $0.isWhitespace }.compactMap { Int32($0) }
                if values.count == 4 {
                    margins = .init(top: CGFloat(values[1]), left: CGFloat(values[0]),
                                    bottom: CGFloat(values[3]), right: CGFloat(values[2]))
                }
            default: break
            }
        }
    }

    @MainActor
    func window(primaryTop: CGFloat, previousID: CGWindowID?) -> (id: CGWindowID, frame: CGRect)? {
        guard target.lowercased() != "fix",
              let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var previous: (CGWindowID, CGRect)?
        for entry in entries {
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), !rect.isEmpty,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue != 0
            else { continue }
            let frame = CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
            if target.hasPrefix("@") {
                let title = entry[kCGWindowName as String] as? String
                if title?.localizedCaseInsensitiveContains(String(target.dropFirst())) == true {
                    return (id, frame)
                }
            } else {
                if pid == frontPID {
                    return (id, frame)
                }
                if id == previousID {
                    previous = (id, frame)
                }
            }
        }
        return previous
    }

    func origin(size: CGSize, target: CGRect?, screen: PresentationScreenGeometry, screens: [PresentationScreenGeometry]) -> CGPoint {
        if let target {
            let candidate = alignedOrigin(size: size, in: target)
            let frame = CGRect(origin: candidate, size: size)
            if skipsClipping || screens.contains(where: { screen in
                let bounds = usesWorkArea ? screen.visibleFrame : screen.frame
                return CGRect(x: bounds.minX - margins.left, y: bounds.minY - margins.bottom,
                              width: bounds.width + margins.left + margins.right,
                              height: bounds.height + margins.bottom + margins.top).contains(frame)
            }) {
                return candidate
            }
        }

        let area = usesWorkArea ? screen.visibleFrame : screen.frame
        let fallback: CGRect = switch side {
        case .center: area
        case .top: CGRect(x: area.minX, y: area.maxY, width: area.width, height: 100)
        case .bottom: CGRect(x: area.minX, y: area.minY - 100, width: area.width, height: 100)
        case .left: CGRect(x: area.minX - 100, y: area.minY, width: 100, height: area.height)
        case .right: CGRect(x: area.maxX, y: area.minY, width: 100, height: area.height)
        }
        return alignedOrigin(size: size, in: fallback)
    }

    private func alignedOrigin(size: CGSize, in rect: CGRect) -> CGPoint {
        let x = corner == .tl || corner == .bl ? rect.minX : rect.maxX - size.width
        let y = corner == .bl || corner == .br ? rect.minY : rect.maxY - size.height
        return CGPoint(x: x + offset.x, y: y + offset.y)
    }
}
