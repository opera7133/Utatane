import Foundation
import GameController

@MainActor
final class GamepadEventMonitor {
    var onEvent: ((String, [Int: String]) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var indices: [ObjectIdentifier: Int] = [:]

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                let identifier = ObjectIdentifier(controller)
                Task { @MainActor in
                    guard let controller = GCController.controllers().first(where: {
                        ObjectIdentifier($0) == identifier
                    }) else { return }
                    self?.connect(controller)
                }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                let identifier = ObjectIdentifier(controller)
                Task { @MainActor in self?.disconnect(identifier) }
            }
        ]
        for controller in GCController.controllers() {
            connect(controller)
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    private func connect(_ controller: GCController) {
        let index = index(for: controller)
        configure(controller, index: index)
        onEvent?("OnGamepadConnected", [0: String(index)])
    }

    private func disconnect(_ identifier: ObjectIdentifier) {
        guard let index = indices.removeValue(forKey: identifier) else { return }
        onEvent?("OnGamepadDisconnected", [0: String(index)])
    }

    private func index(for controller: GCController) -> Int {
        let identifier = ObjectIdentifier(controller)
        if let index = indices[identifier] {
            return index
        }
        let used = Set(indices.values)
        let index = (0...).first { !used.contains($0) } ?? indices.count
        indices[identifier] = index
        return index
    }

    private func configure(_ controller: GCController, index: Int) {
        guard let pad = controller.extendedGamepad else { return }
        let buttons: [(String, GCControllerButtonInput)] = [
            ("A", pad.buttonA), ("B", pad.buttonB), ("X", pad.buttonX), ("Y", pad.buttonY),
            ("L1", pad.leftShoulder), ("R1", pad.rightShoulder),
            ("L2", pad.leftTrigger), ("R2", pad.rightTrigger),
            ("UP", pad.dpad.up), ("DOWN", pad.dpad.down),
            ("LEFT", pad.dpad.left), ("RIGHT", pad.dpad.right)
        ]
        for (name, button) in buttons {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    self?.onEvent?(pressed ? "OnGamepadButtonDown" : "OnGamepadButtonUp", [
                        0: String(index), 1: name
                    ])
                }
            }
        }
        let axes: [(String, GCControllerAxisInput)] = [
            ("LX", pad.leftThumbstick.xAxis), ("LY", pad.leftThumbstick.yAxis),
            ("RX", pad.rightThumbstick.xAxis), ("RY", pad.rightThumbstick.yAxis)
        ]
        for (name, axis) in axes {
            axis.valueChangedHandler = { [weak self] _, value in
                let normalized = abs(value) < 0.08 ? 0 : value
                Task { @MainActor in
                    self?.onEvent?("OnGamepadAxisMove", [
                        0: String(index), 1: name,
                        2: String(Int((normalized * 32767).rounded())),
                        3: String(format: "%.4f", normalized)
                    ])
                }
            }
        }
    }
}
