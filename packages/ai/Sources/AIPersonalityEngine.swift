import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript

public actor AIPersonalityEngine: PersonalityEngine {
    private let manifest: AIGhostManifest
    private let client: any AIProviderClient
    private let now: @Sendable () -> Date
    private var history: [AIConversationMessage] = []
    private var lastSentAt: [String: Date] = [:]

    public init(manifest: AIGhostManifest, client: any AIProviderClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.manifest = manifest
        self.client = client
        self.now = now
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        let date = now()
        let input = AIPersonalityInput(event: event, date: date)
        guard shouldSend(input, at: date) else { return nil }
        do {
            let output = try await client.respond(systemPrompt: manifest.prompt, history: history, input: input)
            remember(input: input, output: output)
            return script(for: output)
        } catch {
            if event == .close {
                return SakuraScript(rawValue: #"\0\s[0]じゃ、また。\-\e"#)
            }
            let output = AIPersonalityOutput(speech: .init(
                text: manifest.fallbackText,
                surface: manifest.fallbackSurface
            ))
            return script(for: output)
        }
    }

    private func shouldSend(_ input: AIPersonalityInput, at date: Date) -> Bool {
        let interval: TimeInterval? = switch input.event {
        case "OnSecondChange": 60
        case "OnMouseMove": 2
        default: nil
        }
        guard let interval else { return true }
        let key = input.event + ":" + (input.references["region"] ?? "")
        if let previous = lastSentAt[key], date.timeIntervalSince(previous) < interval {
            return false
        }
        lastSentAt[key] = date
        return true
    }

    private func remember(input: AIPersonalityInput, output: AIPersonalityOutput) {
        guard let inputData = try? JSONEncoder().encode(input), let outputData = try? JSONEncoder().encode(output) else { return }
        history.append(.init(role: .user, content: String(decoding: inputData, as: UTF8.self)))
        history.append(.init(role: .assistant, content: String(decoding: outputData, as: UTF8.self)))
        if history.count > 20 {
            history.removeFirst(history.count - 20)
        }
    }

    private func script(for output: AIPersonalityOutput) -> SakuraScript? {
        guard let speech = output.speech, !speech.text.isEmpty else { return nil }
        let surface = manifest.allowedSurfaces.contains(speech.surface) ? speech.surface : manifest.fallbackSurface
        let text = Self.escape(speech.text)
        return SakuraScript(rawValue: "\\0\\s[\(surface)]\(text)\\e")
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "￥")
            .replacingOccurrences(of: "%", with: "％")
            .replacingOccurrences(of: "\u{1}", with: "")
    }
}
