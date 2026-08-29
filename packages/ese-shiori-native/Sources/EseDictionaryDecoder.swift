import Foundation
import UtataneCore

public enum EseDictionaryDecoder {
    private static let signature = Data("ESESHIORI".utf8)

    public static func decode(_ data: Data, charset: String = "EUC-KR") -> String? {
        let plain: Data
        if data.starts(with: signature), data.count >= 32 {
            var key = data[9]
            var result = Data(capacity: data.count - 32)
            let payload = data.dropFirst(32)
            for blockStart in stride(from: 0, to: payload.count, by: 64) {
                let block = payload.dropFirst(blockStart).prefix(64)
                for (index, byte) in block.enumerated() {
                    result.append(byte &- (key &+ UInt8(truncatingIfNeeded: index * 5)))
                }
                key &+= 3
            }
            plain = result
        } else {
            plain = data
        }
        return LegacyTextDecoder.decode(plain, preferredCharset: charset)
    }
}
