import AppKit
import SwiftUI
import Testing
@testable import UtatanePlatformMacOS

@MainActor
private final class RuntimeProbe: ObservableObject {
    @Published var showsConsole = true
    var starts = 0
    var ticks = 0
    var ends = 0

    func run() async {
        starts += 1
        defer { ends += 1 }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return
            }
            ticks += 1
        }
    }
}

@MainActor
private func waitForRuntime(_ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
}

@MainActor
private struct RuntimeProbeView: View {
    let tasks: ApplicationRuntimeTasks
    @ObservedObject var probe: RuntimeProbe

    var body: some View {
        ZStack {
            if probe.showsConsole {
                Text("Console")
            } else {
                Color.clear
            }
        }
        .frame(width: 200, height: 100)
        .applicationRuntimeTask(in: tasks, key: "ticker") {
            await probe.run()
        }
    }
}

@MainActor
struct ApplicationRuntimeTasksTests {
    @Test func `registration cancellation does not stop runtime and unchanged revision does not restart it`() async throws {
        let tasks = ApplicationRuntimeTasks()
        let probe = RuntimeProbe()
        defer { tasks.stop() }
        let registration = Task {
            tasks.update(key: "ticker", revision: 0) { await probe.run() }
            try? await Task.sleep(for: .seconds(60))
        }
        try await waitForRuntime { probe.ticks > 0 }
        registration.cancel()
        await registration.value
        let previousTicks = probe.ticks
        tasks.update(key: "ticker", revision: 0) { await probe.run() }
        try await waitForRuntime { probe.ticks > previousTicks }
        #expect(probe.starts == 1)
        #expect(probe.ends == 0)

        tasks.update(key: "ticker", revision: 1) { await probe.run() }
        try await waitForRuntime { probe.starts == 2 && probe.ends == 1 }
        tasks.stop()
        try await waitForRuntime { probe.ends == 2 }
        tasks.update(key: "ticker", revision: 2) { await probe.run() }
        await Task.yield()
        #expect(probe.starts == 2)
    }

    @Test func `completed startup is not repeated on registration`() async throws {
        let tasks = ApplicationRuntimeTasks()
        let probe = RuntimeProbe()
        defer { tasks.stop() }
        tasks.update(key: "startup", revision: 0) { probe.starts += 1 }
        try await waitForRuntime { probe.starts == 1 }
        tasks.update(key: "startup", revision: 0) { probe.starts += 1 }
        await Task.yield()
        #expect(probe.starts == 1)
    }

    @Test func `runtime survives host hiding closing and console toggles`() async throws {
        _ = NSApplication.shared
        let tasks = ApplicationRuntimeTasks()
        let probe = RuntimeProbe()
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: RuntimeProbeView(tasks: tasks, probe: probe))
        window.contentView = hostingView
        let lifetime = RuntimeHostWindowLifetime()
        lifetime.attach(to: window) { probe.showsConsole = false }
        defer {
            tasks.stop()
            window.delegate = nil
            window.close()
        }
        window.orderBack(nil)
        try await waitForRuntime { probe.ticks > 0 }

        for _ in 0 ..< 3 {
            window.orderOut(nil)
            probe.showsConsole = false
            var previousTicks = probe.ticks
            try await waitForRuntime { probe.ticks > previousTicks }
            probe.showsConsole = true
            window.orderBack(nil)
            window.performClose(nil)
            #expect(!window.isVisible)
            #expect(!probe.showsConsole)
            #expect(window.contentView === hostingView)
            previousTicks = probe.ticks
            try await waitForRuntime { probe.ticks > previousTicks }
        }
        #expect(probe.starts == 1)
        #expect(probe.ends == 0)
        tasks.stop()
        try await waitForRuntime { probe.ends == 1 }
    }
}
