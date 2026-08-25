import AppKit
import AVFoundation
import Foundation

public protocol NativeSaoriCalling: Sendable {
    func load(_ path: String)
    func unload(_ path: String)
    func call(_ path: String, arguments: [String]) -> String
}

public struct NativeSaoriWindowFrame: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public protocol NativeSaoriWindowControlling: Sendable {
    func frame(scope: Int) -> NativeSaoriWindowFrame?
    func desktopSize() -> (width: Int, height: Int)
    func move(scope: Int, x: Int, speed: Int)
}

public final class NativeSaoriRegistry: NativeSaoriCalling, @unchecked Sendable {
    private let baseDirectoryURL: URL
    private let windowController: (any NativeSaoriWindowControlling)?
    private var modules: [String: any NativeSaoriModule] = [:]

    public init(baseDirectoryURL: URL, windowController: (any NativeSaoriWindowControlling)? = nil) {
        self.baseDirectoryURL = baseDirectoryURL
        self.windowController = windowController
    }

    public func load(_ path: String) {
        let key = moduleKey(path)
        guard modules[key] == nil else { return }
        switch key {
        case "mciaudior.dll": modules[key] = NativeMciAudioR(baseDirectoryURL: baseDirectoryURL)
        case "wmove.dll": modules[key] = NativeWmove(windowController: windowController)
        case "textcopy2.dll": modules[key] = NativeTextCopy()
        default: break
        }
    }

    public func unload(_ path: String) {
        modules.removeValue(forKey: moduleKey(path))?.unload()
    }

    public func call(_ path: String, arguments: [String]) -> String {
        modules[moduleKey(path)]?.call(arguments) ?? ""
    }

    public func response(path: String, request: String) -> String {
        let arguments = request.components(separatedBy: .newlines).compactMap { line -> (Int, String)? in
            let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard trimmed.lowercased().hasPrefix("argument"), let colon = trimmed.firstIndex(of: ":"),
                  let index = Int(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 8) ..< colon])
            else { return nil }
            return (index, trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }.sorted { $0.0 < $1.0 }.map(\.1)
        guard request.hasPrefix("EXECUTE SAORI/1.") else {
            return request.hasPrefix("GET Version SAORI/1.")
                ? "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\r\n"
                : "SAORI/1.0 400 Bad Request\r\nCharset: Shift_JIS\r\n\r\n"
        }
        let result = call(path, arguments: arguments)
        let values = result.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
        var headers = ""
        if let first = values.first, !first.isEmpty {
            headers += "Result: \(first)\r\n"
        }
        for (index, value) in values.enumerated() where !value.isEmpty {
            headers += "Value\(index): \(value)\r\n"
        }
        return "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\(headers)\r\n"
    }

    private func moduleKey(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last
            .map(String.init)?.lowercased() ?? ""
    }
}

private protocol NativeSaoriModule: AnyObject {
    func call(_ arguments: [String]) -> String
    func unload()
}

private final class NativeTextCopy: NativeSaoriModule {
    func call(_ arguments: [String]) -> String {
        guard let text = arguments.first else { return "" }
        let operation = { @MainActor in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(operation)
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated(operation) }
        }
        return arguments.dropFirst().first == "1" ? text : ""
    }

    func unload() {}
}

private final class NativeMciAudioR: NativeSaoriModule {
    private let baseDirectoryURL: URL
    private var audioURL: URL?
    private var player: AVAudioPlayer?
    private var loops = false

    init(baseDirectoryURL: URL) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func call(_ arguments: [String]) -> String {
        if arguments.count == 2, arguments[0] == "load" {
            stop(); audioURL = resolvedURL(arguments[1])
        } else if arguments == ["stop"] {
            stop()
        } else if arguments == ["loop"] {
            loops = true; togglePlayback()
        } else if arguments == ["play"] {
            togglePlayback()
        }
        return ""
    }

    func unload() {
        stop(); audioURL = nil
    }

    private func togglePlayback() {
        if let player {
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
            return
        }
        guard let audioURL, FileManager.default.fileExists(atPath: audioURL.path),
              let player = try? AVAudioPlayer(contentsOf: audioURL) else { return }
        player.numberOfLoops = loops ? -1 : 0
        player.prepareToPlay(); player.play(); self.player = player
    }

    private func stop() {
        player?.stop(); player = nil
    }

    private func resolvedURL(_ path: String) -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasPrefix("/") ? URL(filePath: normalized).standardizedFileURL
            : baseDirectoryURL.appending(path: normalized).standardizedFileURL
    }
}

private final class NativeWmove: NativeSaoriModule {
    private let windowController: (any NativeSaoriWindowControlling)?

    init(windowController: (any NativeSaoriWindowControlling)?) {
        self.windowController = windowController
    }

    func call(_ arguments: [String]) -> String {
        guard let command = arguments.first?.uppercased() else { return "" }
        switch command {
        case "GET_POSITION":
            guard arguments.count == 2, let scope = scope(arguments[1]),
                  let frame = windowController?.frame(scope: scope) else { return "" }
            return [frame.x, frame.x + frame.width / 2, frame.x + frame.width]
                .map(String.init).joined(separator: "\u{1}")
        case "GET_DESKTOP_SIZE":
            guard arguments.count == 1, let size = windowController?.desktopSize() else { return "" }
            return "\(size.width)\u{1}\(size.height)"
        case "MOVETO", "MOVETO_INSIDE":
            guard arguments.count == 4, let scope = scope(arguments[1]),
                  let x = Int(arguments[2]), let speed = Int(arguments[3]) else { return "" }
            windowController?.move(scope: scope, x: x, speed: max(speed, 0)); return ""
        default: return ""
        }
    }

    func unload() {}

    private func scope(_ identifier: String) -> Int? {
        switch identifier.lowercased() {
        case "0", "sakura": 0
        case "1", "kero": 1
        default: Int(identifier)
        }
    }
}
