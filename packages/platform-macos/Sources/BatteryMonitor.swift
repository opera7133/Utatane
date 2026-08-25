import Foundation
import IOKit.ps

public struct BatterySnapshot: Sendable, Equatable {
    public let percentage: Int
    public let minutesRemaining: Int
    public let powerSource: String
    public let isCharging: Bool
    public let hasBattery: Bool

    public init(
        percentage: Int,
        minutesRemaining: Int,
        powerSource: String,
        isCharging: Bool,
        hasBattery: Bool = true
    ) {
        self.percentage = min(max(percentage, 0), 100)
        self.minutesRemaining = minutesRemaining
        self.powerSource = powerSource
        self.isCharging = isCharging
        self.hasBattery = hasBattery
    }

    public var references: [Int: String] {
        var states: [String] = []
        if !hasBattery {
            states.append("no_battery")
        } else {
            if percentage >= 67 {
                states.append("high")
            }
            if percentage <= 33 {
                states.append("low")
            }
            if percentage <= 5 {
                states.append("critical")
            }
            if isCharging {
                states.append("charging")
            }
        }
        return [
            0: String(percentage),
            1: String(minutesRemaining),
            2: powerSource,
            3: states.joined(separator: ",")
        ]
    }
}

public struct BatteryTransitionDetector: Sendable {
    private var previous: BatterySnapshot?

    public init() {}

    public mutating func consume(_ snapshot: BatterySnapshot) -> [String] {
        defer { previous = snapshot }
        guard let previous else { return ["OnBatteryNotify"] }
        guard snapshot != previous else { return [] }
        var events = ["OnBatteryNotify"]
        if snapshot.hasBattery, snapshot.percentage <= 33, previous.percentage > 33 {
            events.append("OnBatteryLow")
        }
        if snapshot.hasBattery, snapshot.percentage <= 5, previous.percentage > 5 {
            events.append("OnBatteryCritical")
        }
        if snapshot.isCharging != previous.isCharging {
            events.append(snapshot.isCharging ? "OnBatteryChargingStart" : "OnBatteryChargingStop")
        }
        return events
    }
}

public struct MacOSBatterySampler: Sendable {
    public init() {}

    public func sample() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
              as? [String: Any]
        else {
            return BatterySnapshot(
                percentage: 0,
                minutesRemaining: -1,
                powerSource: "online",
                isCharging: false,
                hasBattery: false
            )
        }
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let percentage = Int((Double(current) * 100 / Double(maximum)).rounded())
        let sourceState = description[kIOPSPowerSourceStateKey] as? String
        let powerSource = sourceState == kIOPSBatteryPowerValue ? "offline" : "online"
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let minutes = description[kIOPSTimeToEmptyKey] as? Int ?? -1
        return BatterySnapshot(
            percentage: percentage,
            minutesRemaining: minutes,
            powerSource: powerSource,
            isCharging: charging
        )
    }
}
