import Observation
import UtataneCore
import UtataneRuntime

@MainActor
@Observable
public final class GhostListModel {
    public private(set) var ghosts: [InstalledGhost] = []
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false

    private let loadInstalledGhosts: LoadInstalledGhosts

    public init(loadGhosts: LoadInstalledGhosts) {
        loadInstalledGhosts = loadGhosts
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            ghosts = try await loadInstalledGhosts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
