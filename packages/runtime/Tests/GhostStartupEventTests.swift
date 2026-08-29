import Testing
@testable import UtataneRuntime

@Test(arguments: [false, true])
func `first activation uses OnFirstBoot regardless of how the ghost arrived`(
    arrivedByGhostChange: Bool
) {
    #expect(ghostStartupEventKind(
        hasBooted: false,
        arrivedByGhostChange: arrivedByGhostChange
    ) == .firstBoot)
}

@Test func `later application activation uses OnBoot`() {
    #expect(ghostStartupEventKind(hasBooted: true, arrivedByGhostChange: false) == .boot)
}

@Test func `later ghost switch uses OnGhostChanged`() {
    #expect(ghostStartupEventKind(hasBooted: true, arrivedByGhostChange: true) == .ghostChanged)
}
