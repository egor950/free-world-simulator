import AppKit
import SwiftUI

struct MacKeyboardCapture: NSViewRepresentable {
    let onCommand: (GameCommand) -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onCommand = onCommand
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCatcherView: NSView {
    var onCommand: ((GameCommand) -> Void)?
    private var eKeyDownDate: Date?

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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 14 && !event.isARepeat {
            eKeyDownDate = Date()
            return
        }

        guard let command = command(for: event) else {
            super.keyDown(with: event)
            return
        }

        onCommand?(command)
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 14 else {
            super.keyUp(with: event)
            return
        }

        let pressStartedAt = eKeyDownDate ?? Date()
        eKeyDownDate = nil
        let duration = Date().timeIntervalSince(pressStartedAt)

        if duration >= 0.45 {
            onCommand?(.placeHeldItem)
        } else {
            onCommand?(.primaryAction)
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
        case 34, 53:
            return .inventoryToggle
        default:
            return nil
        }
    }
}
