import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Test @MainActor func `calendar drop accepts URL objects and copied links while preserving ordinary drops`() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    for scheme in ["webcal", "webcals", "https", "http"] {
        pasteboard.clearContents()
        let value = "\(scheme)://example.invalid/calendar.ics?token=a%2Bb"
        pasteboard.setString(value, forType: .URL)
        #expect(SurfaceDropPayload.webURL(from: pasteboard)?.absoluteString == value)
    }
    for scheme in ["webcal", "webcals", "WEBCAL"] {
        pasteboard.clearContents()
        let value = "\(scheme)://example.invalid/feed"
        pasteboard.setString(" \(value)\n", forType: .string)
        #expect(SurfaceDropPayload.webURL(from: pasteboard)?.absoluteString == value)
    }
    for value in ["hello", "https://example.invalid/page", "file:///tmp/test.nar"] {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #expect(SurfaceDropPayload.webURL(from: pasteboard) == nil)
    }
    pasteboard.clearContents()
    pasteboard.setString("file:///tmp/test.nar", forType: .URL)
    #expect(SurfaceDropPayload.webURL(from: pasteboard) == nil)
}
