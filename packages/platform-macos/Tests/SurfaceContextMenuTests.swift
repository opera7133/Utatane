import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Test
@MainActor
func `builds selectable actions and submenus`() throws {
    var performed = false
    let menu = SurfaceContextMenuBuilder().build(from: [
        .submenu(title: "Shell", items: [
            .action(title: "Master", isSelected: true, handler: { performed = true })
        ]),
        .separator,
        .action(title: "Quit", isEnabled: false, handler: {})
    ])

    let shellItem = try #require(menu.items.first)
    let masterItem = try #require(shellItem.submenu?.items.first)
    #expect(masterItem.state == .on)
    #expect(menu.items.last?.isEnabled == false)
    _ = try NSApplication.shared.sendAction(
        #require(masterItem.action),
        to: masterItem.target,
        from: masterItem
    )
    #expect(performed)
}
