import Foundation

extension GameViewModel {
    func handleKeyPress(_ command: GameCommand) {
        switch command {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            if state.controlledCar != nil {
                setDrivingInput(command, isPressed: true)
            } else {
                handle(command)
            }
        default:
            handle(command)
        }
    }

    func handleKeyRelease(_ command: GameCommand) {
        guard state.controlledCar != nil else { return }

        switch command {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            setDrivingInput(command, isPressed: false)
        default:
            break
        }
    }

    func resetDrivingInput() {
        isGasPressed = false
        isBrakePressed = false
        isLeftPressed = false
        isRightPressed = false
        reverseHoldElapsed = 0
        gateAutoPassLockedZ = nil
        for task in pendingDriveCommandResetTasks.values {
            task.cancel()
        }
        pendingDriveCommandResetTasks.removeAll()
    }

    func setDrivingInput(_ command: GameCommand, isPressed: Bool) {
        if isPressed {
            pendingDriveCommandResetTasks[command]?.cancel()
            pendingDriveCommandResetTasks[command] = nil
        }

        switch command {
        case .moveForward:
            isGasPressed = isPressed
        case .moveBackward:
            isBrakePressed = isPressed
        case .moveLeft:
            isLeftPressed = isPressed
        case .moveRight:
            isRightPressed = isPressed
        default:
            break
        }
    }

    func applyDriveCommandImpulse(for command: GameCommand) {
        setDrivingInput(command, isPressed: true)
        pendingDriveCommandResetTasks[command]?.cancel()
        pendingDriveCommandResetTasks[command] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self else { return }
            self.setDrivingInput(command, isPressed: false)
            self.pendingDriveCommandResetTasks[command] = nil
        }
    }
}
