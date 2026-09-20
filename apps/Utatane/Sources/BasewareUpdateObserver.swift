import Foundation
import Sparkle

@MainActor
final class BasewareUpdateObserver: NSObject, SPUUpdaterDelegate {
    private static let pendingUpdateKey = "baseware.pendingUpdatedEvent"

    var onWillInstall: ((_ version: String, _ detailedVersion: String) -> Void)?

    func updater(_: SPUUpdater, willInstallUpdate _: SUAppcastItem) {
        UserDefaults.standard.set(true, forKey: Self.pendingUpdateKey)
        onWillInstall?(Self.currentVersion, Self.currentDetailedVersion)
    }

    func consumePendingUpdatedEvent() -> (version: String, detailedVersion: String)? {
        guard UserDefaults.standard.bool(forKey: Self.pendingUpdateKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: Self.pendingUpdateKey)
        return (Self.currentVersion, Self.currentDetailedVersion)
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static var currentDetailedVersion: String {
        let version = currentVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version).\(build)"
    }
}
