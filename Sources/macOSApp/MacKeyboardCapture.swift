import AppKit
import SwiftUI

struct MacKeyboardCapture: NSViewRepresentable {
    let onInput: (KeyboardInputEvent) -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onInput = onInput
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onInput = onInput
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCatcherView: NSView {
    var onInput: ((KeyboardInputEvent) -> Void)?
    private var eKeyDownDate: Date?
    private var pressedMovementCommands: Set<String> = []

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        releaseAllPressedMovementCommands()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            releaseAllPressedMovementCommands()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 14 && !event.isARepeat {
            eKeyDownDate = Date()
            return
        }

        guard let command = command(for: event) else {
            super.keyDown(with: event)
            return
        }

        switch command {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            pressedMovementCommands.insert(command.rawValue)
            onInput?(.press(command))
        default:
            onInput?(.command(command))
        }
    }

    override func keyUp(with event: NSEvent) {
        if let command = command(for: event) {
            switch command {
            case .moveForward, .moveBackward, .moveLeft, .moveRight:
                pressedMovementCommands.remove(command.rawValue)
                onInput?(.release(command))
            default:
                break
            }
        }

        guard event.keyCode == 14 else {
            super.keyUp(with: event)
            return
        }

        let pressStartedAt = eKeyDownDate ?? Date()
        eKeyDownDate = nil
        let duration = Date().timeIntervalSince(pressStartedAt)

        if duration >= 0.45 {
            onInput?(.command(.placeHeldItem))
        } else {
            onInput?(.command(.primaryAction))
        }
    }

    private func command(for event: NSEvent) -> GameCommand? {
        switch event.keyCode {
        case 123:
            return .moveLeft
        case 124:
            return .moveRight
        case 125:
            return .moveBackward
        case 126:
            return .moveForward
        case 3:
            return .forceAction
        case 12:
            return .describeFocus
        case 15:
            return .describeFocus
        case 49:
            return .throwObject
        case 8:
            return .inventoryQuickAction
        case 7:
            return .locationMenuToggle
        case 36:
            return .locationMenuConfirm
        case 34, 53:
            return .inventoryToggle
        default:
            return nil
        }
    }

    private func releaseAllPressedMovementCommands() {
        let commands = pressedMovementCommands.compactMap(GameCommand.parse)
        pressedMovementCommands.removeAll()
        for command in commands {
            onInput?(.release(command))
        }
    }
}
