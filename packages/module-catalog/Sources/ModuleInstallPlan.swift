import Foundation
import UtataneNetwork

/// A snapshot of everything that can be installed together, plus actionable
/// reasons for entries that need manual intervention.
public struct ModuleInstallPlan: Sendable {
    public enum Reason: Sendable, Equatable {
        case notInCatalog, manualOnly, unsupportedPlatform, unsupportedKind
    }

    public struct Unavailable: Sendable, Equatable {
        public let id: String
        public let reason: Reason
    }

    public let moduleIDs: [String]
    public let unavailable: [Unavailable]

    public init(moduleIDs requested: [String], catalog: SignedModuleCatalog, inventory: ModuleCatalogInventory, requiredKinds: [String: String] = [:]) {
        var ordered: [String] = [], failures: [Unavailable] = [], complete = Set<String>()
        for id in requested where complete.insert(id).inserted {
            guard let module = catalog.modules.first(where: { $0.id == id }) else {
                failures.append(.init(id: id, reason: .notInCatalog)); continue
            }
            guard module.kinds == ["shiori"] || module.kinds == ["saori"],
                  requiredKinds[id].map({ module.kinds.contains($0.lowercased()) }) ?? true
            else {
                failures.append(.init(id: id, reason: .unsupportedKind)); continue
            }
            if inventory.state(for: module) == .current {
                continue
            }
            guard module.availability == "candidate" else {
                failures.append(.init(id: id, reason: .manualOnly)); continue
            }
            guard inventory.artifact(for: module) != nil else {
                failures.append(.init(id: id, reason: .unsupportedPlatform)); continue
            }
            ordered.append(id)
        }
        moduleIDs = ordered
        unavailable = failures
    }
}
