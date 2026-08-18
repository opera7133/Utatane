import Testing
@testable import UtataneSatoriConverter

@Test
func `converts unconditional dialogue and skips control blocks`() {
    let source = """
    ＊通常起動
    ：（０）こんにちは
    ：（１０）やあ

    ＊通常トーク
    ：（５）通常トーク

    ＊条件付き
    ＞別の項目\t（条件）==1
    ：表示しない

    ＊選択後
    ：（２）選んだ
    """

    let result = SatoriDictionaryConverter().convert(source: source)

    #expect(result.catalog.boot == ["\\0\\s[0]こんにちは\\n\\1\\s[10]やあ\\e"])
    #expect(result.catalog.randomTalk == ["\\0\\s[5]通常トーク\\e"])
    #expect(result.catalog.choices["選択後"] == ["\\0\\s[2]選んだ\\e"])
    #expect(result.convertedEntryCount == 3)
    #expect(result.skippedEntryCount == 1)
}

@Test
func `converts inline full width surface numbers and close command`() {
    let source = """
    ＊終了
    ：（０）またね（２４）おやすみ\\-
    """

    let result = SatoriDictionaryConverter().convert(source: source)

    #expect(result.catalog.close == ["\\0\\s[0]またね\\0\\s[24]おやすみ\\e"])
}
