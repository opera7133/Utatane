import Foundation
import Testing
@testable import UtataneAkariNative
import UtataneCore
import UtataneNativeSaori

@Test func `loads plain akari event resources`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）こんにちは。：（１０）相方。
    ＊OnClose
    ・（０）またね。
    """)
    #expect(NativeAkariPersonalityEngine.supports(masterDirectoryURL: master))
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .boot)
    #expect(script?.rawValue == #"\0\s[0]こんにちは。\1\s[10]相方。\e"#)
}

@Test func `substitutes references`() async throws {
    let master = try fixture("""
    ＊OnChoiceSelect
    ・（０）（R0）/（R1）
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .choice(id: "target", arguments: ["value"]))
    #expect(script?.rawValue == #"\0\s[0]target/value\e"#)
}

@Test func `follows conditional jumps and ranges`() async throws {
    let master = try fixture("""
    ＊OnChoiceSelect
    ＞small\t(R1)=1～3
    ＞large
    ＊small
    ・（０）小さい
    ＊large
    ・（０）大きい
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let small = try await engine.handle(event: .choice(id: "size", arguments: ["2"]))
    #expect(small?.rawValue == #"\0\s[0]小さい\e"#)
}

@Test func `evaluates variables words and basic inline functions`() async throws {
    let master = try fixture("""
    ＠挨拶
    やあ
    ＊OnChoiceSelect
    ・（０）(挨拶)、$IF($CMP((R1),2),$INC((R1)),$DIV((R1),2))。$SET(名前,(R0))(名前)
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .choice(id: "灯花", arguments: ["2"]))
    #expect(script?.rawValue == #"\0\s[0]やあ、3。灯花\e"#)
}

@Test func `rejects unknown inline functions`() async throws {
    let master = try fixture("""
    ＊OnClose
    ・$UNKNOWN()
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .close) == nil)
}

@Test func `official sample answers basic lifecycle events when installed`() async throws {
    guard let path = ProcessInfo.processInfo.environment["UTATANE_AKARI_SAMPLE_MASTER"] else { return }
    let master = URL(fileURLWithPath: path, isDirectory: true)
    #expect(NativeAkariPersonalityEngine.supports(masterDirectoryURL: master))
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot) != nil)
    #expect(try await engine.handle(event: .close) != nil)
}

@Test func `persists set variables outside the ghost master`() async throws {
    let master = try fixture("""
    ＊OnChoiceSelect
    ・$SET(名前,(R0))保存した
    ＊OnBoot
    ・（０）(名前)
    """)
    let state = master.deletingLastPathComponent().appending(path: "state/akari-vars.json")
    var engine: NativeAkariPersonalityEngine? = try NativeAkariPersonalityEngine(
        masterDirectoryURL: master,
        variableStoreURL: state
    )
    _ = try await engine?.handle(event: .choice(id: "灯花", arguments: []))
    #expect(FileManager.default.fileExists(atPath: state.path))
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "akari-vars.json").path))

    engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)
    let restored = try await engine?.handle(event: .boot)
    #expect(restored?.rawValue == #"\0\s[0]灯花\e"#)
}

@Test func `evaluates array and dictionary values and functions`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・$SET(配列,{a,b,c})$SET(辞書,${$("one",1),$("two","二")})（０）$ARYVN((配列)):$ARYGET((配列),1):$DICVN((辞書)):$DICGET((辞書),two):$GETTYPE((辞書)):$ARYSTR($STRARY(xy))
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .boot)
    #expect(script?.rawValue == #"\0\s[0]3:b:2:二:dict:xy\e"#)
}

@Test func `persists composite akari values`() async throws {
    let master = try fixture("""
    ＊OnChoiceSelect
    ・$SET(設定,${$("name",(R0))})保存
    ＊OnBoot
    ・（０）$DICGET((設定),name)
    """)
    let state = master.deletingLastPathComponent().appending(path: "state/composite.json")
    var engine: NativeAkariPersonalityEngine? = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)
    _ = try await engine?.handle(event: .choice(id: "灯花", arguments: []))
    engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)
    #expect(try await engine?.handle(event: .boot)?.rawValue == #"\0\s[0]灯花\e"#)
}

@Test func `restores legacy scalar variable json`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）(名前)
    """)
    let state = master.deletingLastPathComponent().appending(path: "state/legacy.json")
    try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(["名前": "灯花"]).write(to: state)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]灯花\e"#)
}

@Test func `executes basic azr functions from inline talk`() async throws {
    let master = try fixture("""
    ＊OnChoiceSelect
    ・（０）$decorate((R0))/$pick({zero,one,two},1)
    """, azr: """
    string decorate(string name)
    {
        string suffix = "!";
        string result = name + suffix;
        return addQuestion(result);
    }

    string addQuestion(string value)
    {
        return value + "?";
    }

    string pick(array values, long index)
    {
        return values[index];
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .choice(id: "灯花", arguments: []))
    #expect(script?.rawValue == #"\0\s[0]灯花!?/one\e"#)
}

@Test func `rejects unsupported azr statements and rolls back globals`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・$complex()
    ＊OnClose
    ・$CMP(remembered,changed)
    """, azr: """
    string complex()
    {
        remembered = "changed";
        switch (1) { return "wrong"; }
        return "also wrong";
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot) == nil)
    #expect(try await engine.handle(event: .close)?.rawValue == #"\00\e"#)
}

@Test func `executes azr conditions loops operators and indexed assignment`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$compute({1,2,3})/$dictionary()
    """, azr: """
    string compute(array values)
    {
        int sum = 0;
        for (int i = 0; i < 3; i++)
        {
            sum += values[i];
        }
        if (sum == 6 && values[0] == 1)
        {
            values[1] = 9;
        }
        int count = 0;
        while (count < 2)
        {
            count++;
        }
        if (count != 2 || sum < 6)
        {
            return "bad";
        }
        else
        {
            return sum + ":" + values[1];
        }
    }

    long dictionary()
    {
        dict values = ${$("count",1)};
        values["count"] += 2;
        return values["count"];
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]6:9/3\e"#)
}

@Test func `executes azr break continue casts ternary and bit operations`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$languageFeatures()
    """, azr: """
    string languageFeatures()
    {
        int total = 0;
        for (int i = 0; i < 8; i++)
        {
            if (i == 1) continue;
            if (i == 5) break;
            total += i;
        }
        string selected = total == 9 ? "yes" : "no";
        return (string)total + ":" + selected + ":" + (1 | 2 * 4) + ":" + ((int)"2" << 2) + ":" + ~0;
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .boot)
    #expect(script?.rawValue == #"\0\s[0]9:yes:9:8:-1\e"#)
}

@Test func `reads master files and writes only to isolated storage`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$fileRoundTrip()
    """, azr: """
    string fileRoundTrip()
    {
        array source = _readtext("data/input.txt", "utf8", "lf");
        int saved = _writetext("data/output.txt", source, "utf8", "lf");
        array copied = _readtext("data/output.txt", "utf8", "lf");
        return source[0] + ":" + copied[1] + ":" + saved + ":" + _isfile("data/output.txt");
    }
    """)
    try FileManager.default.createDirectory(at: master.appending(path: "data"), withIntermediateDirectories: true)
    try "first\nsecond".write(to: master.appending(path: "data/input.txt"), atomically: true, encoding: .utf8)
    let state = master.deletingLastPathComponent().appending(path: "state/akari-vars.json")
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)

    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]first:second:1:1\e"#)
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "data/output.txt").path))
    #expect(FileManager.default.fileExists(atPath: state.deletingLastPathComponent().appending(path: "files/data/output.txt").path))
}

@Test func `enumerates files and indexes function results`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$files()
    """, azr: """
    string files()
    {
        array names = _fenum("data")["file"];
        return _aryvn(names) + ":" + names[0];
    }
    """)
    try FileManager.default.createDirectory(at: master.appending(path: "data"), withIntermediateDirectories: true)
    try "x".write(to: master.appending(path: "data/one.txt"), atomically: true, encoding: .utf8)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]1:one.txt\e"#)
}

@Test func `round trips csv and rejects paths outside the file scope`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$csv()/$escape()/$symlinkEscape()
    """, azr: """
    string csv()
    {
        array rows = {{name,note},{灯花,"a,b"}};
        _savecsv("data/table.csv", rows, "utf8");
        array loaded = _readcsv("data/table.csv", "utf8");
        return _aryget(_aryget(loaded, 1), 1);
    }
    int escape()
    {
        return _writetext("../escape.txt", "bad", "utf8", "lf");
    }
    int symlinkEscape()
    {
        return _writetext("link/escape.txt", "bad", "utf8", "lf");
    }
    """)
    let state = master.deletingLastPathComponent().appending(path: "state/akari-vars.json")
    let files = state.deletingLastPathComponent().appending(path: "files")
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: files.appending(path: "link"), withDestinationURL: master.deletingLastPathComponent())
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]a,b/0/0\e"#)
    #expect(!FileManager.default.fileExists(atPath: state.deletingLastPathComponent().appending(path: "escape.txt").path))
    #expect(!FileManager.default.fileExists(atPath: master.deletingLastPathComponent().appending(path: "escape.txt").path))
}

@Test func `executes azr switch with fallthrough break and default`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$choose(2)/$choose(9)
    """, azr: """
    string choose(int value)
    {
        string result = "";
        switch (value)
        {
        case 1:
            result += "one";
            break;
        case 2:
            result += "two";
        case 3:
            result += "+three";
            break;
        default:
            result = "other";
        }
        return result;
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]two+three/other\e"#)
}

@Test func `evaluates common pure azr library functions`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$pureFunctions()
    """, azr: """
    string echo(string value) { return value; }
    string pureFunctions()
    {
        dict decoded = _json2azv("{\\\"name\\\":\\\"灯花\\\"}");
        array match = _regex_search("abc-12", "([a-z]+)-([0-9]+)");
        return decoded["name"] + ":" + match[2] + ":" + _strstr("abcabc", "bc", 2) + ":" + _fncstr("echo", _base64decode(_base64encode("ok")));
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]灯花:12:4:ok\e"#)
}

@Test func `loads azr globals multiple declarations and composite addition`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$globals()
    """, azr: """
    string helper() { return "ignored"; }
    dict settings = ${$("name","灯花")};
    array seed = {a};
    string globals()
    {
        array values = seed, extra;
        values += "b";
        extra += {x,y};
        dict local;
        local += settings;
        return local["name"] + ":" + values[1] + ":" + extra[1];
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]灯花:b:y\e"#)
}

@Test func `persists azr values and scopes destructive file operations to storage`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$storage()
    """, azr: """
    string storage()
    {
        dict value = ${$("name","灯花")};
        int saved = _vsave("settings", value);
        dict loaded = _vload("settings");
        _dcreate("work");
        _writetext("work/source.txt", "x", "utf8", "lf");
        int copied = _fcopy("work/source.txt", "work/copy.txt");
        int deleted = _fdelete("work/source.txt");
        int protected = _fdelete("res/talk.txt");
        return loaded["name"] + ":" + saved + copied + deleted + protected;
    }
    """)
    let state = master.deletingLastPathComponent().appending(path: "state/akari-vars.json")
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]灯花:1110\e"#)
    #expect(FileManager.default.fileExists(atPath: master.appending(path: "res/talk.txt").path))
}

@Test func `keeps static locals between azr function calls`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$counter()/$counter()
    """, azr: """
    int counter()
    {
        static int count = 0;
        count++;
        return count;
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]1/2\e"#)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]3/4\e"#)
}

@Test func `loads an azr script dynamically within the ghost scope`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$loader()
    """, azr: """
    string loader()
    {
        int loaded = _script_load("res\\late");
        return loaded + ":" + lateFunction();
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    try "string lateFunction() { return \"loaded\"; }".write(
        to: master.appending(path: "res/late.azr"),
        atomically: true,
        encoding: .utf8
    )
    let actual = try await engine.handle(event: .boot)?.rawValue
    #expect(actual == #"\0\s[0]1:loaded\e"#, "actual: \(actual ?? "nil")")
}

@Test func `loads requests and unloads native saori through the shared registry`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$saori()
    """, azr: """
    string saori()
    {
        int loaded = _saoriload("saori_cpuid.dll", "system");
        dict response = _saorirequest("system", "platform");
        int unloaded = _saoriunload("system");
        return loaded + ":" + response["Result"] + ":" + response["Value0"] + ":" + unloaded;
    }
    """)
    let caller = AkariRecordingSaoriCaller()
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, saoriCaller: caller)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]1:macOS:macOS:1\e"#)
    #expect(caller.loads == ["saori_cpuid.dll"])
    #expect(caller.calls == [.init(path: "saori_cpuid.dll", arguments: ["platform"])])
    #expect(caller.unloads == ["saori_cpuid.dll"])
}

@Test func `calls a supported native saori module without wine`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$systemInfo()
    """, azr: """
    string systemInfo()
    {
        dict response = _saorirequest("saori_cpuid.dll", "platform");
        return response["Result"];
    }
    """)
    let engine = try NativeAkariPersonalityEngine(
        masterDirectoryURL: master,
        saoriCaller: NativeSaoriRegistry(baseDirectoryURL: master)
    )
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]macOS\e"#)
}

@Test func `evaluates text conversion formatting token and file hash functions`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$textUtilities()
    """, azr: """
    string textUtilities()
    {
        array tokens = _strtokenize("int value = 1; // ignored");
        array fileTokens = _tokenize("data/source.azr");
        return _zen2han("Ａ１") + ":" + _han2zen("A1") + ":" + _sprintf("%s-%2$s-%3$d", "a", "b", 3) + ":" + tokens[0] + ":" + fileTokens[0] + ":" + _filemd5("data/hash.txt");
    }
    """)
    try FileManager.default.createDirectory(at: master.appending(path: "data"), withIntermediateDirectories: true)
    try "return 1;".write(to: master.appending(path: "data/source.azr"), atomically: true, encoding: .utf8)
    try "abc".write(to: master.appending(path: "data/hash.txt"), atomically: true, encoding: .utf8)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let actual = try await engine.handle(event: .boot)?.rawValue
    #expect(actual == #"\0\s[0]A1:Ａ１:a-b-3:int:return:900150983cd24fb0d6963f7d28e17f72\e"#, "actual: \(actual ?? "nil")")
}

@Test func `fetches bounded http text and downloads into isolated storage`() async throws {
    let master = try fixture("""
    ＊OnBoot
    ・（０）$http()
    """, azr: """
    string http()
    {
        array lines = _httpget("https://example.test/text", "utf8");
        int downloaded = _http_download("https://example.test/file", "downloads/file.bin");
        return lines[0] + ":" + lines[1] + ":" + downloaded + ":" + _isfile("downloads/file.bin");
    }
    """)
    let state = master.deletingLastPathComponent().appending(path: "state/akari-vars.json")
    let fetcher = AkariRecordingHTTPFetcher(responses: [
        "https://example.test/text": Data("first\nsecond".utf8),
        "https://example.test/file": Data([0, 1, 2])
    ])
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master, variableStoreURL: state, httpFetcher: fetcher)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[0]first:second:1:1\e"#)
    #expect(fetcher.maximumBytes == [1_048_576, 8_388_608])
    #expect(try Data(contentsOf: state.deletingLastPathComponent().appending(path: "files/downloads/file.bin")) == Data([0, 1, 2]))
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "downloads/file.bin").path))
}

@Test func `decodes an observed az material box entry`() throws {
    let encoded = try #require(Data(base64Encoded: "AQBBWi1NYXRlcmlhbEJveAAxAFo6L3ByaXZhdGUvdG1wL2FrYXJpLWFtYi5Ib0gwazIvc2NyaXB0L2lucHV0LmF6cgAsAAAAeNorLinKzEtXKCjKT0rV0OSq5lIAgqLUktKiPAWl543rlay5arkYAPkaDBc="))
    let entries = try #require(AkariMaterialBox.decode(encoded))
    #expect(entries.count == 1)
    #expect(entries[0].path.hasSuffix("/input.azr"))
    #expect(String(data: entries[0].data, encoding: .utf8) == "string probe()\n{\n    return \"灯\";\n}\n")
}

@Test func `decodes observed multiple az material box entries`() throws {
    let encoded = try #require(Data(base64Encoded: "AQBBWi1NYXRlcmlhbEJveAA6AFo6L3ByaXZhdGUvdG1wL2FrYXJpLWFtYi5jZWNRZzMvbXVsdGktbWl4ZWQvZnVuY3Rpb25zLmF6cgAsAAAAeNorLinKzEtXyEjNKUgt0tDkquZSAIKi1JLSojwFJYiwkjVXLRcDACvLDOg3AFo6L3ByaXZhdGUvdG1wL2FrYXJpLWFtYi5jZWNRZzMvbXVsdGktbWl4ZWQvZXZlbnRzLnR4dAAgAAAAeNp7v6fLP88pP7+E63Hz7hiD3NKcksyYVC4GAJHOCjQ="))
    let entries = try #require(AkariMaterialBox.decode(encoded))
    #expect(entries.map(\.path).map { URL(fileURLWithPath: $0).lastPathComponent } == ["functions.azr", "events.txt"])
    #expect(String(data: entries[0].data, encoding: .utf8)?.contains("string helper()") == true)
    #expect(String(data: entries[1].data, encoding: .utf8) == "＊OnBoot\n・\\0multi\\e\n")
}

@Test func `loads event resources from an observed multiple entry material box`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try "shiori,akari.dll\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    let encoded = try #require(Data(base64Encoded: "AQBBWi1NYXRlcmlhbEJveAA6AFo6L3ByaXZhdGUvdG1wL2FrYXJpLWFtYi5jZWNRZzMvbXVsdGktbWl4ZWQvZnVuY3Rpb25zLmF6cgAsAAAAeNorLinKzEtXyEjNKUgt0tDkquZSAIKi1JLSojwFJYiwkjVXLRcDACvLDOg3AFo6L3ByaXZhdGUvdG1wL2FrYXJpLWFtYi5jZWNRZzMvbXVsdGktbWl4ZWQvZXZlbnRzLnR4dAAgAAAAeNp7v6fLP88pP7+E63Hz7hiD3NKcksyYVC4GAJHOCjQ="))
    try encoded.write(to: master.appending(path: "main.amb"))
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    let actual = try await engine.handle(event: .boot)?.rawValue
    #expect(actual == "\\0\\0multi\\e\n\\e", "actual: \(actual ?? "nil")")
}

@Test func `dispatches an azr event function without a plain event resource`() async throws {
    let master = try fixture("", azr: """
    string OnBoot(dict ref)
    {
        return "\\0" + ref["ID"] + "\\e";
    }
    """)
    let engine = try NativeAkariPersonalityEngine(masterDirectoryURL: master)
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0OnBoot\e"#)
}

private func fixture(_ resource: String, azr: String? = nil) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    let res = master.appending(path: "res", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
    try "shiori,akari.dll\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    try resource.write(to: res.appending(path: "talk.txt"), atomically: true, encoding: .utf8)
    if let azr {
        try azr.write(to: master.appending(path: "functions.azr"), atomically: true, encoding: .utf8)
    }
    return master
}

private final class AkariRecordingSaoriCaller: NativeSaoriCalling, @unchecked Sendable {
    struct Call: Equatable {
        let path: String
        let arguments: [String]
    }

    var loads: [String] = []
    var calls: [Call] = []
    var unloads: [String] = []

    func load(_ path: String) {
        loads.append(path)
    }

    func unload(_ path: String) {
        unloads.append(path)
    }

    func call(_ path: String, arguments: [String]) -> String {
        calls.append(.init(path: path, arguments: arguments))
        return "macOS\u{1}macOS"
    }
}

private final class AkariRecordingHTTPFetcher: AkariHTTPFetching, @unchecked Sendable {
    let responses: [String: Data]
    var maximumBytes: [Int] = []

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func fetch(url: URL, maximumBytes: Int) -> Data? {
        self.maximumBytes.append(maximumBytes)
        return responses[url.absoluteString]
    }
}
