import Foundation
import UtataneShell

@MainActor
public final class DressupSelectionStore {
    private let defaults: UserDefaults
    private let namespace: String
    private var contentID: URL?

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = "dev.utatane.dressup-selection"
    ) {
        self.defaults = defaults
        self.namespace = namespace
    }

    public func setContentID(_ contentID: URL?) {
        self.contentID = contentID?.standardizedFileURL
    }

    func restore(for shell: ShellDefinition) -> [Int: Set<Int>]? {
        guard let data = defaults.data(forKey: key(for: shell)),
              let stored = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return nil }

        var result: [Int: Set<Int>] = [:]
        for (scopeString, ids) in stored {
            guard let scope = Int(scopeString), let groups = shell.bindGroups[scope] else { continue }
            result[scope] = Set(ids).intersection(groups.keys)
        }
        return normalized(result, for: shell)
    }

    func save(_ bindings: [Int: Set<Int>], for shell: ShellDefinition) {
        let value = normalized(bindings, for: shell).reduce(into: [String: [Int]]()) { result, entry in
            result[String(entry.key)] = entry.value.sorted()
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key(for: shell))
    }

    private func normalized(_ bindings: [Int: Set<Int>], for shell: ShellDefinition) -> [Int: Set<Int>] {
        var result: [Int: Set<Int>] = [:]
        for (scope, groups) in shell.bindGroups {
            var selected = (bindings[scope] ?? []).intersection(groups.keys)
            let categories = Dictionary(grouping: groups.values, by: \.category)
            for (category, categoryGroups) in categories {
                let options = shell.bindOptions[scope]?[category] ?? ShellBindOptions()
                let categoryIDs = Set(categoryGroups.map(\.id))
                let selectedCategoryIDs = selected.intersection(categoryIDs)
                if !options.multiple, selectedCategoryIDs.count > 1,
                   let retained = selectedCategoryIDs.sorted().first
                {
                    selected.subtract(categoryIDs)
                    selected.insert(retained)
                } else if options.mustSelect, selectedCategoryIDs.isEmpty,
                          let fallback = shell.defaultBindGroups[scope]?.intersection(categoryIDs).sorted().first
                          ?? categoryIDs.sorted().first
                {
                    selected.insert(fallback)
                }
            }
            result[scope] = selected
        }
        return result
    }

    private func key(for shell: ShellDefinition) -> String {
        let content = contentID?.path ?? "global"
        let identity = "\(content)\u{0}\(shell.directory.standardizedFileURL.path)"
        let encoded = Data(identity.utf8).base64EncodedString()
        return "\(namespace).\(encoded)"
    }
}
