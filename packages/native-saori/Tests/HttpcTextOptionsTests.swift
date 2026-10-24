import Foundation
import Testing
@testable import UtataneNativeSaori

@Test func `httpc options preserve original tag conversions and extraction order`() {
    var arguments = ["erase_tag", "utf8", "translate_tag", "https://example.invalid"]
    let options = HttpcTextOptions(arguments: &arguments)
    #expect(arguments == ["https://example.invalid"])
    #expect(options.charset == "UTF-8")
    #expect(options.process(#"<P>Title<br><br><a href="https://example.invalid">Link</a><img alt="代替">&nbsp;&lt;&gt;&amp;&copy;<hr>End"#) == #"\nTitle\n\_a[https://example.invalid]Link\_a〔代替〕<>\&(c)\n-----------------------------------------------\nEnd"#)
    var eraseArguments = ["erase_tag"]
    let erase = HttpcTextOptions(arguments: &eraseArguments)
    #expect(erase.process("<b>日本語</b>\r\n&amp;<unfinished") == "日本語&amp;")
    #expect(options.process(String(repeating: "a", count: 6000)).count == 119 * 48)
    #expect(options.process(String(repeating: "あ", count: 6000)).count == 119 * 24)
    #expect(options.process(String(repeating: "😀", count: 6000)).count == 119 * 24)
    #expect(options.process("<a = href='url'>safe</a>") == #"safe\_a"#)
}
