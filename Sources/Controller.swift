// T3d Boy — game controller support via Apple's GameController framework.
// Covers DualShock 4 / DualSense, Xbox One/Series, Switch Pro, and MFi pads
// paired over Bluetooth or USB; macOS normalizes them all to one profile.

import Foundation
import GameController

final class GamepadManager {
    static let shared = GamepadManager()

    // The joypad of the frontmost game window; set by GameWindowController
    weak var joypad: Joypad?
    var currentControllerName: String?
    var onStatusChange: (() -> Void)?

    func start() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            if let controller = note.object as? GCController {
                self?.configure(controller)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.currentControllerName = GCController.controllers().first?.vendorName
            self.onStatusChange?()
        }
        GCController.controllers().forEach(configure)
    }

    private func configure(_ controller: GCController) {
        currentControllerName = controller.vendorName ?? "Controller"
        onStatusChange?()

        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] pad, _ in
            guard let joypad = self?.joypad else { return }
            let dpad = pad.dpad
            let stick = pad.leftThumbstick
            joypad.set(.up, pressed: dpad.up.isPressed || stick.yAxis.value > 0.5)
            joypad.set(.down, pressed: dpad.down.isPressed || stick.yAxis.value < -0.5)
            joypad.set(.left, pressed: dpad.left.isPressed || stick.xAxis.value < -0.5)
            joypad.set(.right, pressed: dpad.right.isPressed || stick.xAxis.value > 0.5)
            // Positional mapping to the Game Boy's layout: east button
            // (Circle / Xbox B) = A, south button (Cross / Xbox A) = B
            joypad.set(.a, pressed: pad.buttonB.isPressed)
            joypad.set(.b, pressed: pad.buttonA.isPressed)
            joypad.set(.start, pressed: pad.buttonMenu.isPressed)
            joypad.set(.selectBtn, pressed: pad.buttonOptions?.isPressed ?? false)
        }
    }
}
