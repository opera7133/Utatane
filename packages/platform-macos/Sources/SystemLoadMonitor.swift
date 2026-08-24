import Darwin
import Foundation

public struct SystemLoadPercentages: Sendable, Equatable {
    public let cpu: Int
    public let memory: Int

    public init(cpu: Int, memory: Int) {
        self.cpu = min(max(cpu, 0), 100)
        self.memory = min(max(memory, 0), 100)
    }
}

public struct SystemLoadTransitions: Sendable, Equatable {
    public var cpuBecameHigh = false
    public var cpuBecameLow = false
    public var memoryBecameHigh = false
    public var memoryBecameLow = false

    public init() {}
}

public struct SystemLoadTransitionDetector: Sendable {
    private let highThreshold: Int
    private let lowThreshold: Int
    private let samplesRequiredForHigh: Int
    private var consecutiveHighCPU = 0
    private var consecutiveHighMemory = 0
    private var isCPUHigh = false
    private var isMemoryHigh = false

    public init(
        highThreshold: Int = 80,
        lowThreshold: Int = 60,
        samplesRequiredForHigh: Int = 3
    ) {
        self.highThreshold = highThreshold
        self.lowThreshold = lowThreshold
        self.samplesRequiredForHigh = max(samplesRequiredForHigh, 1)
    }

    public mutating func consume(_ sample: SystemLoadPercentages) -> SystemLoadTransitions {
        var transitions = SystemLoadTransitions()
        update(
            value: sample.cpu,
            consecutiveHigh: &consecutiveHighCPU,
            isHigh: &isCPUHigh,
            becameHigh: &transitions.cpuBecameHigh,
            becameLow: &transitions.cpuBecameLow
        )
        update(
            value: sample.memory,
            consecutiveHigh: &consecutiveHighMemory,
            isHigh: &isMemoryHigh,
            becameHigh: &transitions.memoryBecameHigh,
            becameLow: &transitions.memoryBecameLow
        )
        return transitions
    }

    private func update(
        value: Int,
        consecutiveHigh: inout Int,
        isHigh: inout Bool,
        becameHigh: inout Bool,
        becameLow: inout Bool
    ) {
        if isHigh {
            if value < lowThreshold {
                isHigh = false
                consecutiveHigh = 0
                becameLow = true
            }
            return
        }
        consecutiveHigh = value >= highThreshold ? consecutiveHigh + 1 : 0
        if consecutiveHigh >= samplesRequiredForHigh {
            isHigh = true
            consecutiveHigh = 0
            becameHigh = true
        }
    }
}

public final class MacOSSystemLoadSampler: @unchecked Sendable {
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?

    public init() {}

    public func sample() -> SystemLoadPercentages? {
        guard let cpu = cpuPercentage(), let memory = memoryPercentage() else { return nil }
        return SystemLoadPercentages(cpu: cpu, memory: memory)
    }

    private func cpuPercentage() -> Int? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let busy = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.3)
        let total = busy + UInt64(info.cpu_ticks.2)
        defer { previousCPUTicks = (busy, total) }
        guard let previousCPUTicks, total > previousCPUTicks.total else { return 0 }
        let busyDelta = busy - previousCPUTicks.busy
        let totalDelta = total - previousCPUTicks.total
        return Int((Double(busyDelta) * 100 / Double(totalDelta)).rounded())
    }

    private func memoryPercentage() -> Int? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let usedPages = UInt64(info.active_count)
            + UInt64(info.wire_count)
            + UInt64(info.compressor_page_count)
        let usedBytes = usedPages * UInt64(getpagesize())
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }
        return Int((Double(usedBytes) * 100 / Double(totalBytes)).rounded())
    }
}
