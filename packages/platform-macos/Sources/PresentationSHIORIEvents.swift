import AppKit
import UtataneCore

public extension PresentationGeometryProviding {
    func displayChangeEvents(isInitial: Bool = false) -> [GhostEvent] {
        let primary = mainScreen
        let basic: [Int: String] = primary.map {
            [0: String($0.bitsPerPixel), 1: String(Int($0.frame.width)), 2: String(Int($0.frame.height))]
        } ?? [:]
        var extended = [0: isInitial ? "init" : "update"]
        let top = primary?.frame.maxY ?? 0
        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            extended[index + 1] = [
                Int(frame.minX), Int(top - frame.maxY), Int(frame.maxX), Int(top - frame.minY),
                screen.bitsPerPixel, screen.isPrimary ? 1 : 0
            ].map(String.init).joined(separator: ",") + ",unknown,0"
        }
        return [("OnDisplayChange", basic), ("OnDisplayChangeEx", extended)].map { id, references in
            isInitial ? .notification(id: id, references: references) : .shiori(id: id, references: references)
        }
    }
}

public extension SurfaceWindowController {
    func surfaceChangeEvent(scope: Int, surfaceID changedID: Int) -> GhostEvent {
        let size = changedID >= 0 ? (renderedImage(for: scope)?.size ?? .zero) : .zero
        return .notification(id: "OnSurfaceChange", references: [
            0: String(scope == 0 ? changedID : (surfaceID(for: 0) ?? -1)),
            1: String(scope == 1 ? changedID : (surfaceID(for: 1) ?? -1)),
            2: [scope, changedID, Int(size.width), Int(size.height)]
                .map(String.init).joined(separator: ",")
        ])
    }
}
