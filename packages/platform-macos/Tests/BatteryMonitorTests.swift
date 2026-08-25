import Testing
@testable import UtatanePlatformMacOS

@Test
func `battery snapshot uses UKADOC reference values`() {
    let snapshot = BatterySnapshot(
        percentage: 5,
        minutesRemaining: 12,
        powerSource: "offline",
        isCharging: true
    )
    #expect(snapshot.references == [
        0: "5", 1: "12", 2: "offline", 3: "low,critical,charging"
    ])
}

@Test
func `battery transitions only emit when state crosses a boundary`() {
    var detector = BatteryTransitionDetector()
    #expect(detector.consume(.init(
        percentage: 80, minutesRemaining: 120, powerSource: "offline", isCharging: false
    )) == ["OnBatteryNotify"])
    #expect(detector.consume(.init(
        percentage: 33, minutesRemaining: 60, powerSource: "offline", isCharging: false
    )) == ["OnBatteryNotify", "OnBatteryLow"])
    #expect(detector.consume(.init(
        percentage: 5, minutesRemaining: 10, powerSource: "online", isCharging: true
    )) == ["OnBatteryNotify", "OnBatteryCritical", "OnBatteryChargingStart"])
    #expect(detector.consume(.init(
        percentage: 5, minutesRemaining: 10, powerSource: "online", isCharging: true
    )).isEmpty)
    #expect(detector.consume(.init(
        percentage: 6, minutesRemaining: 12, powerSource: "online", isCharging: false
    )) == ["OnBatteryNotify", "OnBatteryChargingStop"])
}
