import CUtataneModuleABI
import Darwin
import Foundation
import UtataneNativeSaori

/// The session retains this object until the module can no longer call the host.
final class UtataneModuleHostServices {
    private let caller: any NativeSaoriCalling
    private var loadedPaths: Set<String> = []

    init(caller: any NativeSaoriCalling) {
        self.caller = caller
    }

    func unloadAll() {
        for path in loadedPaths {
            caller.unload(path)
        }
        loadedPaths.removeAll()
    }

    func invoke(operation: UInt32, path: String, arguments: [String]) -> String? {
        switch operation {
        case UInt32(UM_SAORI_LOAD):
            guard arguments.isEmpty else { return nil }
            caller.load(path)
            loadedPaths.insert(path)
            return ""
        case UInt32(UM_SAORI_UNLOAD):
            guard arguments.isEmpty else { return nil }
            caller.unload(path)
            loadedPaths.remove(path)
            return ""
        case UInt32(UM_SAORI_CALL):
            return caller.call(path, arguments: arguments)
        default: return nil
        }
    }
}

private func decode(_ span: UMBytes) -> String? {
    guard span.length <= UM_MAX_BYTES else { return nil }
    if span.length == 0 {
        return ""
    }
    guard let pointer = span.data,
          let value = String(bytes: UnsafeBufferPointer(start: pointer, count: Int(span.length)), encoding: .utf8),
          !value.contains("\0") else { return nil }
    return value
}

let utataneModuleSaoriCallback: UMSaori = { context, operation, path, arguments, count, output in
    guard let context, let output, output.pointee.data == nil, output.pointee.length == 0,
          count <= 65536, count == 0 || arguments != nil, let path = decode(path) else { return Int32(UM_INVALID) }
    var values: [String] = []
    for span in UnsafeBufferPointer(start: arguments, count: Int(count)) {
        guard let value = decode(span) else { return Int32(UM_INVALID) }
        values.append(value)
    }
    let host = Unmanaged<UtataneModuleHostServices>.fromOpaque(context).takeUnretainedValue()
    guard let value = host.invoke(operation: operation, path: path, arguments: values) else { return Int32(UM_INVALID) }
    let bytes = Array(value.utf8)
    guard bytes.count <= UM_MAX_BYTES, !value.contains("\0") else { return Int32(UM_HOST) }
    if bytes.isEmpty {
        return Int32(UM_OK)
    }
    guard let pointer = malloc(bytes.count)?.assumingMemoryBound(to: UInt8.self) else { return Int32(UM_ALLOCATION) }
    pointer.initialize(from: bytes, count: bytes.count)
    output.pointee = UMBuffer(data: pointer, length: UInt32(bytes.count))
    return Int32(UM_OK)
}

let utataneModuleHostRelease: UMHostRelease = { _, buffer in
    guard let buffer else { return }
    free(buffer.pointee.data)
    buffer.pointee = UMBuffer()
}
