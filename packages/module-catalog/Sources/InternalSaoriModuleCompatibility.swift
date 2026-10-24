import Foundation

/// Minimum public builds containing the parent-host internal SAORI callback.
/// Unknown/custom libraries are not classified using their filenames alone.
public struct InternalSaoriModuleRequirement: Equatable, Sendable {
    public let moduleID: String
    public let version: String
    public let revision: Int

    public var label: String {
        "\(version)-r\(revision)"
    }

    public static func minimum(for moduleID: String) -> Self? {
        let version: String
        let revision: Int
        switch moduleID {
        case "yaya": version = "Tc574-11"; revision = 2
        case "yaya-6": version = "Tc607-2"; revision = 2
        case "satori": version = "Mc205-4"; revision = 2
        case "kawari": version = "9.1.0"; revision = 4
        default: return nil
        }
        return Self(moduleID: moduleID, version: version, revision: revision)
    }
}
