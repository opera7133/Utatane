import Darwin
import Foundation
import UtataneNativeSaori
import UtataneShiori

public enum NativeMisakaError: LocalizedError, Sendable {
    case missingConfiguration(URL)

    public var errorDescription: String? {
        switch self {
        case let .missingConfiguration(url): "MISAKA設定が見つからない: \(url.path)"
        }
    }
}

public final class NativeMisakaSession: @unchecked Sendable {
    private let lock = NSLock()
    private let masterDirectoryURL: URL
    private let variableStoreURL: URL
    private let startedAt: Date
    private let now: @Sendable () -> Date
    private var restoredTotalSeconds = 0
    private var firstBootAt: Date
    private var nextRandomTalkAt: Date?
    private var scheduledTalkInterval: Int?
    private var evaluator: MisakaEvaluator

    public convenience init(masterDirectoryURL: URL, variableStoreURL: URL? = nil) throws {
        try self.init(
            masterDirectoryURL: masterDirectoryURL,
            variableStoreURL: variableStoreURL,
            saoriCaller: NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL),
            now: Date.init
        )
    }

    init(
        masterDirectoryURL: URL,
        variableStoreURL: URL? = nil,
        saoriCaller: any NativeSaoriCalling,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        let iniURL = masterDirectoryURL.appending(path: "misaka.ini")
        guard FileManager.default.fileExists(atPath: iniURL.path) else {
            throw NativeMisakaError.missingConfiguration(iniURL)
        }
        self.masterDirectoryURL = masterDirectoryURL
        self.variableStoreURL = variableStoreURL ?? masterDirectoryURL.appending(path: "misaka_vars.json")
        self.now = now
        startedAt = now()
        firstBootAt = startedAt
        evaluator = try MisakaEvaluator(dictionary: MisakaDictionary.load(masterDirectoryURL: masterDirectoryURL))
        evaluator.saoriCaller = saoriCaller
        updateSystemVariables(at: startedAt)
        _ = evaluator.evaluate(symbol: "$_Variable")
        if let data = try? Data(contentsOf: self.variableStoreURL),
           let saved = try? JSONDecoder().decode([String: [String]].self, from: data)
        {
            evaluator.variables.merge(saved) { _, saved in saved }
        }
        restoredTotalSeconds = Int(evaluator.variables["__utatane.totalSeconds"]?.first ?? "0") ?? 0
        firstBootAt = evaluator.variables["__utatane.firstBoot"]?.first.flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:)) ?? startedAt
        updateSystemVariables(at: startedAt)
        _ = evaluator.evaluate(symbol: "$_Constant")
        scheduleNextRandomTalk(at: startedAt)
        writeDiagnosticsIfNeeded()
    }

    deinit {
        try? save()
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        try lock.withLock {
            guard let id = request.id else {
                return ShioriResponse(statusCode: 204, reasonPhrase: "No Content")
            }
            if id.caseInsensitiveCompare("version") == .orderedSame {
                return Self.response(value: "Utatane MISAKA Native/0.1")
            }
            evaluator.references = Dictionary(uniqueKeysWithValues: (0 ... 15).compactMap { index in
                request.reference(index).map { (index, $0) }
            })
            evaluator.extraHeaders = []
            let requestDate = now()
            updateSystemVariables(at: requestDate)
            if let sender = request.headers["Sender"] {
                evaluator.variables["sender"] = [sender]
            }
            if id == "OnCommunicate" {
                evaluator.variables["sender"] = [request.reference(0) ?? ""]
                evaluator.variables["lastsentence"] = [request.reference(1) ?? ""]
            }
            if id == "OnMouseMove" {
                let key = [request.reference(3) ?? "0", request.reference(4) ?? ""].joined(separator: ":")
                evaluator.mouseMoveCounts[key, default: 0] += 1
            }
            updateOtherGhostList(id: id, request: request)
            let symbol = switch id {
            case "OnAITalk": "$_OnRandomTalk"
            case "OnCommunicate": "$_OnGhostCommunicateReceive"
            default: "$" + id
            }
            var value = evaluator.evaluate(symbol: symbol)
            let currentTalkInterval = evaluator.variables["_talkinterval"]?.first.flatMap(Int.init)
            if currentTalkInterval != scheduledTalkInterval {
                scheduleNextRandomTalk(at: requestDate)
            }
            if id == "OnSecondChange", shouldRunRandomTalk(at: requestDate) {
                let randomTalk = evaluator.evaluate(symbol: "$_OnRandomTalk")
                if !randomTalk.isEmpty {
                    value = randomTalk
                }
                scheduleNextRandomTalk(at: requestDate)
            }
            writeDebugRequest(id: id, value: value)
            writeSaoriDebugEntries()
            if id == "OnClose" || evaluator.backupRequested {
                try saveUnlocked()
                evaluator.backupRequested = false
            }
            return value.isEmpty
                ? ShioriResponse(statusCode: 204, reasonPhrase: "No Content")
                : Self.response(value: value, extraHeaders: responseHeaders())
        }
    }

    public func save() throws {
        try lock.withLock {
            try saveUnlocked()
        }
    }

    private func saveUnlocked() throws {
        let elapsed = max(0, Int(now().timeIntervalSince(startedAt)))
        evaluator.variables["__utatane.totalSeconds"] = [String(restoredTotalSeconds + elapsed)]
        evaluator.variables["__utatane.firstBoot"] = [String(firstBootAt.timeIntervalSince1970)]
        let data = try JSONEncoder().encode(evaluator.variables.filter { !Self.transientVariables.contains($0.key) })
        try FileManager.default.createDirectory(
            at: variableStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: variableStoreURL, options: .atomic)
    }

    private func responseHeaders() -> [ShioriHeader] {
        var headers = evaluator.extraHeaders
        if let target = evaluator.variables["to"]?.first, !target.isEmpty {
            headers.append(ShioriHeader(name: "Reference0", value: target))
            evaluator.variables["to"] = [""]
        }
        return headers
    }

    private static func response(value: String, extraHeaders: [ShioriHeader] = []) -> ShioriResponse {
        ShioriResponse(
            statusCode: 200,
            reasonPhrase: "OK",
            headers: ShioriHeaders([
                ShioriHeader(name: "Charset", value: "UTF-8"),
                ShioriHeader(name: "Sender", value: "UtataneMisakaNative"),
                ShioriHeader(name: "Value", value: value)
            ] + extraHeaders)
        )
    }

    private static var transientVariables: Set<String> {
        systemVariableNames.union(["sender", "lastsentence", "name"])
    }

    private static var systemVariableNames: Set<String> {
        [
            "year", "month", "day", "hour", "minute", "second", "dayofweek", "mode",
            "elapsedhour", "elapsedminute", "elapsedsecond", "elapsedhouros", "elapsedminuteos", "elapsedsecondos",
            "elapsedhourtotal", "elapsedminutetotal", "elapsedsecondtotal", "os.name", "os.version",
            "os.phisicalmemorysize", "os.freememorysize", "os.totalmemorysize", "cpu.vendorname", "cpu.name",
            "cpu.clockcycle", "daysfromlastupdate", "daysfromfirstboot", "otherghostlist", "hwnd.sakura", "hwnd.kero",
            "hwnd.sakuraballoon", "hwnd.keroballoon"
        ]
    }

    private func updateSystemVariables(at date: Date) {
        for (name, value) in systemVariables(at: date) {
            evaluator.variables[name] = value
        }
    }

    private func systemVariables(at date: Date) -> [String: [String]] {
        let calendar = Calendar.current
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
        let total = restoredTotalSeconds + elapsed
        let memory = Self.memoryInformation()
        let lastUpdate = (try? masterDirectoryURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? startedAt
        return [
            "year": [String(calendar.component(.year, from: date))],
            "month": [String(calendar.component(.month, from: date))],
            "day": [String(calendar.component(.day, from: date))],
            "hour": [String(calendar.component(.hour, from: date))],
            "minute": [String(calendar.component(.minute, from: date))],
            "second": [String(calendar.component(.second, from: date))],
            "dayofweek": [String(calendar.component(.weekday, from: date) - 1)],
            "mode": ["0"],
            "elapsedhour": [String(elapsed / 3600)],
            "elapsedminute": [String(elapsed / 60)],
            "elapsedsecond": [String(elapsed)],
            "elapsedhouros": [String(Int(ProcessInfo.processInfo.systemUptime) / 3600)],
            "elapsedminuteos": [String(Int(ProcessInfo.processInfo.systemUptime) / 60)],
            "elapsedsecondos": [String(Int(ProcessInfo.processInfo.systemUptime))],
            "elapsedhourtotal": [String(total / 3600)],
            "elapsedminutetotal": [String(total / 60)],
            "elapsedsecondtotal": [String(total)],
            "os.name": ["macOS"],
            "os.version": [ProcessInfo.processInfo.operatingSystemVersionString],
            "os.phisicalmemorysize": [String(ProcessInfo.processInfo.physicalMemory)],
            "os.freememorysize": [String(memory.free)],
            "os.totalmemorysize": [String(ProcessInfo.processInfo.physicalMemory)],
            "cpu.vendorname": [Self.sysctlString("machdep.cpu.vendor") ?? "Apple"],
            "cpu.name": [Self.sysctlString("machdep.cpu.brand_string") ?? Self.sysctlString("hw.model") ?? "Unknown"],
            "cpu.clockcycle": [String((Self.sysctlUInt64("hw.cpufrequency") ?? 0) / 1_000_000)],
            "daysfromlastupdate": [String(max(0, calendar.dateComponents([.day], from: lastUpdate, to: date).day ?? 0))],
            "daysfromfirstboot": [String(max(0, calendar.dateComponents([.day], from: firstBootAt, to: date).day ?? 0))],
            "hwnd.sakura": ["0"],
            "hwnd.kero": ["1"],
            "hwnd.sakuraballoon": ["0"],
            "hwnd.keroballoon": ["0"]
        ]
    }

    private func shouldRunRandomTalk(at date: Date) -> Bool {
        nextRandomTalkAt.map { date >= $0 } ?? false
    }

    private func scheduleNextRandomTalk(at date: Date) {
        guard let interval = evaluator.variables["_talkinterval"]?.first.flatMap(Int.init), interval > 0 else {
            scheduledTalkInterval = evaluator.variables["_talkinterval"]?.first.flatMap(Int.init)
            nextRandomTalkAt = nil
            return
        }
        scheduledTalkInterval = interval
        nextRandomTalkAt = date.addingTimeInterval(Double(interval) * Double.random(in: 0.5 ... 1.5))
    }

    private func writeDiagnosticsIfNeeded() {
        guard evaluator.dictionary.errorEnabled else { return }
        let text = evaluator.dictionary.diagnostics.isEmpty
            ? "MISAKA native: no load errors detected.\n"
            : evaluator.dictionary.diagnostics.joined(separator: "\n") + "\n"
        try? writeLog(named: "misaka_error.txt", text: text, append: false)
    }

    private func writeDebugRequest(id: String, value: String) {
        guard evaluator.dictionary.debugEnabled else { return }
        try? writeLog(named: "misaka_debug.txt", text: "\(Date()) \(id) -> \(value)\n", append: true)
    }

    private func writeSaoriDebugEntries() {
        defer { evaluator.saoriDebugEntries = [] }
        guard evaluator.dictionary.debugSaoriEnabled, !evaluator.saoriDebugEntries.isEmpty else { return }
        let text = evaluator.saoriDebugEntries.map { "\(Date()) \($0)\n" }.joined()
        try? writeLog(named: "misaka_debugsaori.txt", text: text, append: true)
    }

    private func updateOtherGhostList(id: String, request: ShioriRequest) {
        var names = evaluator.variables["otherghostlist"] ?? []
        if id.caseInsensitiveCompare("otherghostname") == .orderedSame {
            names = (0 ... 15).compactMap { request.reference($0) }.compactMap {
                $0.split(separator: "\u{1}", omittingEmptySubsequences: false).first.map(String.init)
            }.filter { !$0.isEmpty }
        } else if id == "OnOtherGhostBooted", let name = request.reference(0), !names.contains(name) {
            names.append(name)
        } else if id == "OnOtherGhostClosed", let name = request.reference(0) {
            names.removeAll { $0 == name }
        }
        evaluator.variables["otherghostlist"] = names
    }

    private func writeLog(named name: String, text: String, append: Bool) throws {
        let url = variableStoreURL.deletingLastPathComponent().appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if append, let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private static func memoryInformation() -> (free: UInt64, total: UInt64) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, ProcessInfo.processInfo.physicalMemory) }
        let pageSize = UInt64(getpagesize())
        return (UInt64(statistics.free_count + statistics.inactive_count) * pageSize, ProcessInfo.processInfo.physicalMemory)
    }
}
