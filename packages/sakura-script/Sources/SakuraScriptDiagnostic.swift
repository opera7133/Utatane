import Foundation

public struct SakuraScriptDiagnostic: Equatable, Sendable {
    public let message: String
    public let range: Range<Int>
}

public extension SakuraScriptParser {
    func diagnostics(_ source: String) -> [SakuraScriptDiagnostic] {
        parseLocated(source).compactMap { located in
            let message: String? = switch located.token {
            case let .unknown(tag): "未知または不正なタグ: " + tag
            case let .scope(id) where id < 0: "不正なスコープID"
            case let .balloonSurface(id) where id < -1: "不正なバルーンID"
            case let .lineBreak(scale) where scale.map { $0 < 0 } == true: "不正な改行倍率"
            case let .choice(label, id, _) where label.isEmpty || id.isEmpty: "空の選択肢ラベルまたはID"
            default: nil
            }
            return message.map { SakuraScriptDiagnostic(message: $0, range: located.location.range) }
        }
    }
}
