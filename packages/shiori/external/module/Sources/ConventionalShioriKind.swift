import Foundation

public enum ConventionalShioriKind: String, Sendable {
    case minato
    case pasta
    case niseshiori = "nise-shiori"
    case eseShiori = "ese-shiori"
    case yuhna
    case hisui
    case shino
    case akari
    case kawari

    public var libraryFilename: String {
        self == .niseshiori ? "libniseshiori.dylib" : "lib\(rawValue).dylib"
    }

    public init?(libraryFilename: String) {
        switch libraryFilename.lowercased() {
        case "libminato.dylib": self = .minato
        case "libpasta.dylib": self = .pasta
        case "libniseshiori.dylib": self = .niseshiori
        case "libese-shiori.dylib": self = .eseShiori
        case "libyuhna.dylib": self = .yuhna
        case "libhisui.dylib": self = .hisui
        case "libshino.dylib": self = .shino
        case "libakari.dylib": self = .akari
        case "libkawari.dylib": self = .kawari
        default: return nil
        }
    }

    public init?(shioriFilename: String?) {
        let filename = shioriFilename?.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased()
        switch filename {
        case "minato.dll", "libminato.dylib": self = .minato
        case "pasta.dll", "libpasta.dylib": self = .pasta
        case "niseshiori.dll", "libniseshiori.dylib": self = .niseshiori
        case "ese-shiori.dll", "libese-shiori.dylib": self = .eseShiori
        case "yuhna.dll", "libyuhna.dylib": self = .yuhna
        case "hisui.dll", "libhisui.dylib": self = .hisui
        case "shino.dll", "libshino.dylib": self = .shino
        case "akari.dll", "libakari.dylib": self = .akari
        case "kawari.dll", "libkawari.dylib": self = .kawari
        default: return nil
        }
    }
}
