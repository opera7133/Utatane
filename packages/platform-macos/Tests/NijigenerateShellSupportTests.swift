import AppKit
import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test func `nijigenerate runtime requires puppet and library`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = directory.appending(path: "libnicxlive.dylib")
    #expect(NijigenerateShellRuntime.locate(
        shellDirectory: directory,
        environment: ["UTATANE_NICXLIVE_LIBRARY": library.path]
    ) == nil)

    try Data().write(to: directory.appending(path: "puppet.inp"))
    try Data().write(to: library)
    try Data(#"{"viewport":{"width":480,"height":760,"contentScale":0.94,"contentOffsetY":24,"interactionOffsetY":12,"interactionScaleX":1.25,"interactionScaleY":1.5},"pointer":{"centerX":160,"centerY":150,"rangeX":140,"rangeY":120},"parameters":{"Expression::Smile":0},"surfaces":{"105":{"Expression::Smile":1}},"reactions":[{"event":"doubleClick","region":"Head","durationMilliseconds":2500,"parameters":{"Expression::Smile":1}}]}"#.utf8)
        .write(to: directory.appending(path: "nijigenerate.json"))
    #expect(NijigenerateShellRuntime.locate(
        shellDirectory: directory,
        environment: ["UTATANE_NICXLIVE_LIBRARY": library.path]
    ) == NijigenerateShellRuntime(
        puppetURL: directory.appending(path: "puppet.inp"),
        libraryURL: library,
        configuration: NijigenerateShellConfiguration(
            viewport: .init(
                width: 480,
                height: 760,
                contentScale: 0.94,
                contentOffsetY: 24,
                interactionOffsetY: 12,
                interactionScaleX: 1.25,
                interactionScaleY: 1.5
            ),
            pointer: .init(centerX: 160, centerY: 150, rangeX: 140, rangeY: 120),
            parameters: ["Expression::Smile": 0],
            surfaces: ["105": ["Expression::Smile": 1]],
            reactions: [
                NijigenerateReactionConfiguration(
                    event: "doubleClick",
                    region: "Head",
                    durationMilliseconds: 2500,
                    parameters: ["Expression::Smile": 1]
                )
            ]
        )
    ))
    let configuration = NijigenerateShellRuntime.locate(
        shellDirectory: directory,
        environment: ["UTATANE_NICXLIVE_LIBRARY": library.path]
    )?.configuration
    #expect(configuration?.parameters(for: 0)["Expression::Smile"] == 0)
    #expect(configuration?.parameters(for: 105)["Expression::Smile"] == 1)
    #expect(configuration?.viewport.size == NSSize(width: 480, height: 760))
    #expect(configuration?.viewport.safeContentScale == 0.94)
    #expect(configuration?.viewport.contentOffsetY == 24)
    #expect(configuration?.viewport.interactionOffsetY == 12)
    #expect(configuration?.viewport.interactionScaleX == 1.25)
    #expect(configuration?.viewport.interactionScaleY == 1.5)
    #expect(configuration?.pointer?.values(x: 300, y: 30).x == 1)
    #expect(configuration?.pointer?.values(x: 300, y: 30).y == 1)
    #expect(configuration?.pointer?.values(x: 20, y: 270).x == -1)
    #expect(configuration?.pointer?.values(x: 20, y: 270).y == -1)
    #expect(configuration?.pointer?.safeResponse == 0.35)
    #expect(configuration?.reactions.first?.matches(event: "doubleclick", region: "head", button: 0) == true)
    #expect(configuration?.reactions.first?.matches(event: "click", region: "Head", button: 0) == false)
    #expect(configuration?.reactions.first?.transitionMilliseconds == 120)
    #expect(configuration?.reactions.first?.restoreMilliseconds == 220)

    let installedRuntimeRoot = directory.appending(path: "Application Support", directoryHint: .isDirectory)
    let installedLibrary = installedRuntimeRoot
        .appending(path: "Utatane/Runtimes/nicxlive/libnicxlive.dylib")
    try FileManager.default.createDirectory(
        at: installedLibrary.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data().write(to: installedLibrary)
    #expect(NijigenerateShellRuntime.locate(
        shellDirectory: directory,
        environment: [:],
        applicationSupportDirectory: installedRuntimeRoot
    )?.libraryURL == installedLibrary)

    let externalPuppet = directory.appending(path: "smoke.inp")
    try Data().write(to: externalPuppet)
    #expect(NijigenerateShellRuntime.locate(
        shellDirectory: URL(filePath: "/unused"),
        environment: [
            "UTATANE_NIJIGENERATE_PUPPET": externalPuppet.path,
            "UTATANE_NICXLIVE_LIBRARY": library.path
        ]
    )?.puppetURL == externalPuppet)
}

@Test @MainActor func `nijigenerate renderer loads local smoke puppet when configured`() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let puppetPath = environment["UTATANE_NICXLIVE_SMOKE_PUPPET"],
          let libraryPath = environment["UTATANE_NICXLIVE_LIBRARY"]
    else { return }
    let runtime = NijigenerateShellRuntime(
        puppetURL: URL(filePath: puppetPath),
        libraryURL: URL(filePath: libraryPath)
    )
    let view = try NijigenerateViewFactory.make(
        runtime: runtime,
        size: NSSize(width: 720, height: 720)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.orderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    NijigenerateViewFactory.setScale(NSSize(width: 0.5, height: 0.5), on: view)
    #expect(NijigenerateViewFactory.setParameter("Body::Roll", valueX: 0.25, on: view))
    let additionalParameter = environment["UTATANE_NICXLIVE_SMOKE_PARAMETER"] ?? "Expression::Smile"
    #expect(NijigenerateViewFactory.setParameter(additionalParameter, valueX: 1, on: view))
    #expect(!NijigenerateViewFactory.setParameter("Missing::Parameter", valueX: 1, on: view))
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
    window.orderOut(nil)
    window.contentView = nil
    #expect(view.frame.size == NSSize(width: 720, height: 720))
}
