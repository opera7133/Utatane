public enum LegacyMateriaScriptNormalizer {
    /// Maps Materia's kero-local surface numbers (0...9) to shell IDs (10...19).
    public static func normalizeKeroSurfaces(in script: String, initialScope: Int = 0) -> String {
        let characters = Array(script)
        var result = ""
        var index = 0
        var scope = initialScope

        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                result.append(characters[index])
                index += 1
                continue
            }
            let command = characters[index + 1]
            if command == "0" || command == "h" {
                scope = 0
            } else if command == "1" || command == "u" {
                scope = 1
            } else if command == "p", index + 3 < characters.count,
                      characters[index + 2] == "[",
                      let closing = characters[(index + 3)...].firstIndex(of: "]"),
                      let selectedScope = Int(String(characters[(index + 3) ..< closing]))
            {
                scope = selectedScope
            }
            guard command == "s", scope == 1 else {
                result.append(characters[index])
                result.append(command)
                index += 2
                continue
            }

            if index + 2 < characters.count,
               let surface = characters[index + 2].wholeNumberValue
            {
                result += "\\s[\(surface + 10)]"
                index += 3
            } else if index + 3 < characters.count, characters[index + 2] == "[",
                      let closing = characters[(index + 3)...].firstIndex(of: "]"),
                      let surface = Int(String(characters[(index + 3) ..< closing])),
                      (0 ... 9).contains(surface)
            {
                result += "\\s[\(surface + 10)]"
                index = closing + 1
            } else {
                result += "\\s"
                index += 2
            }
        }
        return result
    }
}
