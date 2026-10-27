import Foundation
import UtataneLZMA

struct LZMAArchiveEntry {
    let archiveData: Data
    let payloadRange: Range<Int>
    let uncompressedSize: UInt64
    let checksum: UInt32
    let requiresEndMarker: Bool

    func extract(consumer: @escaping (Data) throws -> Void) throws {
        let state = LZMAConsumer(consumer)
        let result = archiveData.withUnsafeBytes { bytes in
            utatane_lzma_decode(bytes.bindMemory(to: UInt8.self).baseAddress?.advanced(by: payloadRange.lowerBound), payloadRange.count, uncompressedSize, checksum,
                                requiresEndMarker ? 1 : 0, { bytes, count, context in
                                    guard let context, let bytes else { return 0 }
                                    let state = Unmanaged<LZMAConsumer>.fromOpaque(context).takeUnretainedValue()
                                    do { try state.consumer(Data(bytes: bytes, count: count)); return 1 }
                                    catch { state.error = error; return 0 }
                                }, Unmanaged.passUnretained(state).toOpaque())
        }
        if let error = state.error {
            throw error
        }
        guard result == 0 else { throw LZMAArchiveError.invalidStream }
    }
}

private enum LZMAArchiveError: LocalizedError {
    case invalidStream
    var errorDescription: String? {
        "LZMAデータを復元できません。破損、サイズ、CRC、辞書サイズの上限を確認してください。"
    }
}

private final class LZMAConsumer {
    let consumer: (Data) throws -> Void
    var error: Error?
    init(_ consumer: @escaping (Data) throws -> Void) {
        self.consumer = consumer
    }
}
