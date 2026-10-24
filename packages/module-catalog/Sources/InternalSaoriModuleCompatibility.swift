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

    public static func minimumForDiagnostics(for moduleID: String) -> Self? {
        let version: String, revision: Int
        switch moduleID {
        case "yaya": version = "Tc574-11"; revision = 3
        case "yaya-6": version = "Tc607-2"; revision = 3
        case "satori": version = "Mc205-5"; revision = 1
        case "kawari": version = "9.2.0"; revision = 1
        case "shino": version = "0.9.7"; revision = 3
        case "akari": version = "2.003"; revision = 3
        default: return nil
        }
        return Self(moduleID: moduleID, version: version, revision: revision)
    }
}
