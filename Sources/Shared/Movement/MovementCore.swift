import Foundation

extension GameViewModel {
    func announceMovementNode(_ node: FocusNode) {
        let prompt = currentShortPrompt()
        if !prompt.isEmpty {
            announce(prompt)
            return
        }

        if case .none = node.target, node.title == "асфальт" {
            announce("Асфальт.")
            return
        }

        announce("Рядом \(node.title).")
    }

    func movePlayer(_ command: GameCommand) {
        lastMovementAt = Date()

        if poseMachine.isStanding,
           let door = doorAtCurrentPosition(),
           shouldPassThroughDoor(door, on: command) {
            tryPassThroughDoor(door)
            return
        }

        if !poseMachine.isStanding {
            guard let linearStep = linearStep(for: command) else { return }
            if command == .moveLeft || command == .moveRight {
                audioCoordinator.playBlockedMovement()
                announce("Ты на кровати. Влево и вправо нельзя, можно только вперед и назад.")
                return
            }

            moveAlongBed(step: linearStep)
            return
        }

        switch currentTraversalMode {
        case .linearPath:
            moveAlongRoom(command)
        case .freeGrid4Way:
            moveFreely(command)
        }
    }

    func canMoveNow() -> Bool {
        Date().timeIntervalSince(lastMovementAt) >= movementStepInterval
    }

    func completeMovement(to position: GridPosition, focusTarget: FocusTarget) {
        if poseMachine.isLying {
            setPlayerPose(.crawling)
        }

        state.player.roomPosition = position
        state.player.focusedTarget = normalizedFocusTarget(focusTarget)
        audioCoordinator.playStep()
        refreshScreenState()

        if let hint = currentNavigationBeaconHint() {
            setSilentStatus("\(ui.statusText) Маяк: \(hint)")
        }
    }

    func shouldPassThroughDoor(_ door: DoorDefinition, on command: GameCommand) -> Bool {
        if currentTraversalMode == .freeGrid4Way {
            let position = state.player.roomPosition
            var validCommands: [GameCommand] = []

            if position.y == 0 {
                validCommands.append(.moveForward)
            }
            if position.y == currentRoom.height - 1 {
                validCommands.append(.moveBackward)
            }
            if position.x == 0 {
                validCommands.append(.moveLeft)
            }
            if position.x == currentRoom.width - 1 {
                validCommands.append(.moveRight)
            }

            return validCommands.contains(command)
        }

        let path = roomPath(for: currentRoom.id)
        guard let first = path.first, let last = path.last else { return false }

        if state.player.roomPosition == first {
            return command == .moveBackward || command == .moveLeft
        }

        if state.player.roomPosition == last {
            return command == .moveForward || command == .moveRight
        }

        return false
    }
}
