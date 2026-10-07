import Foundation
import UtataneCore

public extension SakuraScriptPlayer {
    func runtimePropertyValue(for property: String) -> String? {
        let key = property.lowercased()
        if key == "currentghost.status" {
            return executionStatus
        }
        if key == "currentghost.seriko.sticky-window" {
            return surfaceWindowController.stickyWindowGroups.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";")
        }
        guard let (scope, field) = Self.scopeProperty(key) else { return nil }
        switch field {
        case "surface.num": return surfaceWindowController.surfaceID(for: scope).map(String.init)
        case "animation.num": return surfaceWindowController.runningAnimationIDs(for: scope).map(String.init).joined(separator: ",")
        case "seriko.defaultsurface": return surfaceWindowController.defaultSurfaceID(for: scope).map(String.init)
        default: return nil
        }
    }

    @discardableResult
    func setRuntimeProperty(_ value: String, for property: String) throws -> Bool {
        let key = property.lowercased()
        if key == "currentghost.seriko.sticky-window" {
            let groups = value.split(separator: ";").compactMap { group -> [Int]? in
                let fields = group.split(separator: ",", omittingEmptySubsequences: false)
                let scopes = fields.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                return scopes.count == fields.count ? scopes : nil
            }
            surfaceWindowController.replaceStickyWindowGroups(groups)
            return true
        }
        guard let (scope, field) = Self.scopeProperty(key) else { return false }
        switch field {
        case "surface.num":
            guard let id = Int(value) else { throw PropertySystemError.readOnlyProperty(property) }
            try surfaceWindowController.changeSurface(scope: scope, to: id)
        case "animation.num":
            let fields = value.split(separator: ",", omittingEmptySubsequences: false)
            let ids = fields.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard ids.count == fields.count, ids.allSatisfy({ $0 >= 0 }) else { throw PropertySystemError.readOnlyProperty(property) }
            for id in ids {
                surfaceWindowController.playAnimation(id: id, scope: scope)
            }
        case "seriko.defaultsurface":
            guard let id = Int(value), id >= 0 else { throw PropertySystemError.readOnlyProperty(property) }
            surfaceWindowController.setDefaultSurfaceID(id, scope: scope)
        default: return false
        }
        return true
    }

    private static func scopeProperty(_ property: String) -> (Int, String)? {
        let prefix = "currentghost.scope("
        guard property.hasPrefix(prefix), let end = property.firstIndex(of: ")"),
              let scope = Int(property[property.index(property.startIndex, offsetBy: prefix.count) ..< end]), scope >= 0 else { return nil }
        let suffix = property[property.index(after: end)...]
        guard suffix.hasPrefix(".") else { return nil }
        return (scope, String(suffix.dropFirst()))
    }
}
