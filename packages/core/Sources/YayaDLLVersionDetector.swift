import Foundation

/// Reads the Windows VERSIONINFO resource without loading or executing the DLL.
public enum YayaDLLVersionDetector {
    public enum MajorVersion: Equatable, Sendable {
        case five
        case six
        case unknown
    }

    public static func detect(at url: URL) -> MajorVersion {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.int64Value <= 256 * 1024 * 1024,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return .unknown }
        return detect(in: data)
    }

    public static func detect(in data: Data) -> MajorVersion {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int? {
            guard offset >= 0, offset <= bytes.count - 2 else { return nil }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) -> Int? {
            guard offset >= 0, offset <= bytes.count - 4 else { return nil }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        guard u16(0) == 0x5A4D, let pe = u32(0x3C), u32(pe) == 0x0000_4550,
              let sectionCount = u16(pe + 6), sectionCount > 0, sectionCount <= 96,
              let optionalSize = u16(pe + 20), let magic = u16(pe + 24)
        else { return .unknown }
        let optional = pe + 24
        let directoryOffset: Int
        switch magic {
        case 0x10B: directoryOffset = 96
        case 0x20B: directoryOffset = 112
        default: return .unknown
        }
        guard optionalSize >= directoryOffset + 24,
              let resourceRVA = u32(optional + directoryOffset + 16), resourceRVA != 0,
              let resourceSize = u32(optional + directoryOffset + 20), resourceSize >= 24
        else { return .unknown }
        let sections = optional + optionalSize
        func fileOffset(_ rva: Int) -> Int? {
            for index in 0 ..< sectionCount {
                let section = sections + index * 40
                guard let virtualSize = u32(section + 8), let base = u32(section + 12),
                      let rawSize = u32(section + 16), let raw = u32(section + 20)
                else { return nil }
                let length = max(virtualSize, rawSize)
                if rva >= base, rva - base < length, rva - base < rawSize {
                    let offset = raw + rva - base
                    return offset >= 0 && offset < bytes.count ? offset : nil
                }
            }
            return nil
        }
        guard let root = fileOffset(resourceRVA) else { return .unknown }
        func directoryChild(_ directory: Int, id: Int?) -> (Int, Bool)? {
            guard let named = u16(directory + 12), let numbered = u16(directory + 14),
                  named + numbered <= 4096
            else { return nil }
            for index in 0 ..< named + numbered {
                let entry = directory + 16 + index * 8
                guard let name = u32(entry), let value = u32(entry + 4) else { return nil }
                if let id, name != id {
                    continue
                }
                if id == nil, name & 0x8000_0000 != 0 {
                    continue
                }
                let relative = value & 0x7FFF_FFFF
                guard relative < resourceSize,
                      let offset = fileOffset(resourceRVA + relative)
                else {
                    return nil
                }
                return (offset, value & 0x8000_0000 != 0)
            }
            return nil
        }
        guard let type = directoryChild(root, id: 16), type.1,
              let name = directoryChild(type.0, id: nil), name.1,
              let language = directoryChild(name.0, id: nil), !language.1,
              let versionRVA = u32(language.0), let versionSize = u32(language.0 + 4),
              versionSize >= 92, let version = fileOffset(versionRVA),
              versionSize <= bytes.count - version,
              let blockLength = u16(version), blockLength <= versionSize,
              let valueLength = u16(version + 2), valueLength >= 52
        else { return .unknown }
        let key = Array("VS_VERSION_INFO".utf16)
        for (index, unit) in key.enumerated() where u16(version + 6 + index * 2) != Int(unit) {
            return .unknown
        }
        let value = (version + 6 + (key.count + 1) * 2 + 3) & ~3
        guard value + 52 <= version + blockLength,
              u32(value) == 0xFEEF_04BD, u32(value + 4) == 0x0001_0000,
              let fileVersion = u32(value + 8)
        else { return .unknown }
        switch fileVersion >> 16 {
        case 5: return .five
        case 6: return .six
        default: return .unknown
        }
    }
}
