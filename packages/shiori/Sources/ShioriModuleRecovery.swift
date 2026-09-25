import Foundation

/// Retry only before a module has initialized its dictionary or persistent state.
public enum ShioriModuleRecovery {
    public static func load<T>(
        preferred: URL,
        fallback: URL?,
        canRecover: (Error) -> Bool,
        using load: (URL) throws -> T
    ) throws -> T {
        do { return try load(preferred) }
        catch {
            guard canRecover(error), let fallback, fallback != preferred else { throw error }
            let original = error
            do {
                let result = try load(fallback)
                NSLog("SHIORI fallback: %@ -> %@ (%@)", preferred.path, fallback.path, original.localizedDescription)
                return result
            } catch {
                throw RecoveryError(preferred: preferred, original: original, fallback: fallback, failure: error)
            }
        }
    }

    private struct RecoveryError: LocalizedError {
        let preferred: URL
        let original: Error
        let fallback: URL
        let failure: Error

        var errorDescription: String? {
            "\(preferred.path): \(original.localizedDescription)\n\(fallback.path): \(failure.localizedDescription)"
        }
    }
}
