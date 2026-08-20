import Testing
@testable import UtatanePlatformMacOS

@Test(arguments: [
    ("このゴーストのSHIORIにはまだ対応していない: foo.dll", "このゴーストはまだ起動できない"),
    ("aosora用のネイティブSHIORIが見つからない。", "ネイティブSHIORIが見つからない"),
    ("FIRSTを起動するためのWine設定が足りない。", "Windows互換機能を起動できない"),
    ("SATORIがゴーストを読み込めなかった", "ゴーストの人格を起動できない"),
    ("よく分からない失敗", "エラー")
])
func `classifies application error titles`(_ message: String, _ expectedTitle: String) {
    #expect(ApplicationErrorPresentation(message: message).title == expectedTitle)
}
