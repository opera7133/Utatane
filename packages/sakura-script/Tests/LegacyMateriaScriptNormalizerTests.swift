import Testing
@testable import UtataneSakuraScript

@Test func `Materia click wait resets speaker before mapping subsequent surfaces`() {
    #expect(LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(in: #"\1\s0\x\c\s5"#) == #"\1\s[10]\x\c\s5"#)
    #expect(LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(in: #"\p[1]\s[3]\x\s[5]\1\s2"#) == #"\p[1]\s[13]\x\s[5]\1\s[12]"#)
    #expect(LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(in: #"\x\s5"#, initialScope: 1) == #"\x\s5"#)
}

@Test func `Materia normalizer retains speaker across noclear click waits`() {
    #expect(LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(in: #"\1\s0\x[noclear]\s5"#) == #"\1\s[10]\x[noclear]\s[15]"#)
}
