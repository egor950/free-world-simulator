import Foundation

extension GameViewModel {
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

    func linearStep(for command: GameCommand) -> Int? {
        switch command {
        case .moveForward:
            return 1
        case .moveBackward:
            return -1
        case .moveLeft:
            return -1
        case .moveRight:
            return 1
        default:
            return nil
        }
    }

    func blockedText(for command: GameCommand) -> String {
        if currentTraversalMode == .freeGrid4Way {
        switch command {
        case .moveForward:
            switch currentRoom.id {
            case .street:
                return "Дальше только калитка и край дороги."
            case .mainStreet:
                return "Дальше пока только край широкой улицы."
            default:
                return "Дальше хода нет."
            }
        case .moveBackward:
            switch currentRoom.id {
            case .street:
                return "Дальше уже стена дома и дверь позади."
            case .mainStreet:
                return "Позади только калитка и край улицы."
            default:
                return "Дальше хода нет."
            }
        case .moveLeft:
            switch currentRoom.id {
            case .street:
                return "Слева дальше уже стена дома."
            case .mainStreet:
                return "Слева дальше уже край улицы."
            default:
                return "Дальше хода нет."
            }
        case .moveRight:
            switch currentRoom.id {
            case .street:
                return "Справа дальше уже край двора."
            case .mainStreet:
                return "Справа дальше уже край улицы."
            default:
                return "Дальше хода нет."
            }
        default:
            return "Дальше хода нет."
        }
        }

        switch command {
        case .moveForward:
            return "Дальше по комнате пути нет."
        case .moveBackward:
            return "Назад дальше пути нет."
        case .moveLeft:
            return "Назад дальше пути нет."
        case .moveRight:
            return "Дальше по комнате пути нет."
        default:
            return "Дальше стена."
        }
    }

    func movementDelta(for command: GameCommand) -> GridPosition? {
        switch command {
        case .moveForward:
            return GridPosition(x: 0, y: -1)
        case .moveBackward:
            return GridPosition(x: 0, y: 1)
        case .moveLeft:
            return GridPosition(x: -1, y: 0)
        case .moveRight:
            return GridPosition(x: 1, y: 0)
        default:
            return nil
        }
    }

    func completeMovement(to position: GridPosition, focusTarget: FocusTarget) {
        if poseMachine.isLying {
            setPlayerPose(.crawling)
        }

        state.player.roomPosition = position
        state.player.focusedTarget = normalizedFocusTarget(focusTarget)
        audioCoordinator.playStep()
        refreshScreenState()
    }

    func moveAlongRoom(_ command: GameCommand) {
        guard let step = linearRoomStep(for: command) else {
            return
        }

        let path = roomPath(for: currentRoom.id)
        let currentIndex = currentLinearRoomIndex(in: path)
        let nextIndex = currentIndex + step

        guard nextIndex >= 0, nextIndex < path.count else {
            audioCoordinator.playBlockedMovement()
            announce(blockedText(for: command))
            return
        }

        let nextPosition = path[nextIndex]
        let focusTarget = visibleNode(at: nextPosition)?.target ?? .none

        if command == .moveBackward,
           case let .door(id) = focusTarget,
           let door = currentRoom.doors[id],
           isDoorOpened(door) {
            state.player.roomPosition = nextPosition
            state.player.focusedTarget = .door(id)
            refreshScreenState()
            tryPassThroughDoor(door)
            return
        }

        completeMovement(to: nextPosition, focusTarget: focusTarget)

        if let node = visibleNode(at: nextPosition) {
            addLog("Рядом: \(node.title)")
            let prompt = currentShortPrompt()
            if prompt.isEmpty {
                announce("Рядом \(node.title).")
            } else {
                announce(prompt)
            }
        } else {
            setSilentStatus("Ты двигаешься дальше по комнате.")
        }
    }

    func moveFreely(_ command: GameCommand) {
        guard let delta = movementDelta(for: command) else {
            return
        }

        let nextPosition = GridPosition(
            x: state.player.roomPosition.x + delta.x,
            y: state.player.roomPosition.y + delta.y
        )

        guard nextPosition.x >= 0,
              nextPosition.y >= 0,
              nextPosition.x < currentRoom.width,
              nextPosition.y < currentRoom.height else {
            audioCoordinator.playBlockedMovement()
            announce(blockedText(for: command))
            return
        }

        let focusTarget = visibleNode(at: nextPosition)?.target ?? .none
        completeMovement(to: nextPosition, focusTarget: focusTarget)

        if let node = visibleNode(at: nextPosition) {
            addLog("Рядом: \(node.title)")
            let prompt = currentShortPrompt()
            if prompt.isEmpty {
                announce("Рядом \(node.title).")
            } else {
                announce(prompt)
            }
        } else if currentRoom.id == .street {
            if let hint = nearestStreetCarGuidance(maxDistance: 6, includeDistance: true, parkedOnly: true) {
                setSilentStatus("Ты идешь по асфальту. \(hint)")
            } else {
                setSilentStatus("Ты идешь по асфальту.")
            }
        } else if currentRoom.id == .mainStreet {
            setSilentStatus("Ты идешь по асфальту.")
        } else {
            setSilentStatus("Ты двигаешься дальше.")
        }
    }

    func moveAlongBed(step: Int) {
        let anchor = bedAnchorPosition ?? state.player.roomPosition
        bedAnchorPosition = anchor
        let trackLength = linearTrackLength()
        let anchorIndex = linearIndex(for: anchor)
        let currentIndex = linearIndex(for: state.player.roomPosition)
        let minIndex = max(0, anchorIndex - 1)
        let maxIndex = min(trackLength - 1, anchorIndex + 1)
        let nextIndex = currentIndex + step

        guard nextIndex >= minIndex && nextIndex <= maxIndex else {
            audioCoordinator.playBlockedMovement()
            announce("Край кровати. Дальше нельзя, можно упасть.")
            return
        }

        let nextPosition = position(forClampedLinearIndex: nextIndex)
        let focusTarget = visibleNode(at: nextPosition)?.target ?? .none
        completeMovement(to: nextPosition, focusTarget: focusTarget)

        if let node = visibleNode(at: nextPosition) {
            addLog("Рядом: \(node.title)")
            let prompt = currentShortPrompt()
            if prompt.isEmpty {
                announce("Рядом \(node.title).")
            } else {
                announce(prompt)
            }
        } else {
            setSilentStatus("Ты подтягиваешься по кровати.")
        }
    }

    func syncBedAnchorAfterAction() {
        if poseMachine.isStanding {
            bedAnchorPosition = nil
            return
        }

        if let focusedItem = currentFocusItem, focusedItem.id == BedroomBed.itemID {
            bedAnchorPosition = state.player.roomPosition
        } else if bedAnchorPosition == nil {
            bedAnchorPosition = state.player.roomPosition
        }

        state.player.focusedTarget = normalizedFocusTarget(state.player.focusedTarget)
    }

    func linearTrackLength() -> Int {
        max(1, currentRoom.width * currentRoom.height)
    }

    func linearRoomStep(for command: GameCommand) -> Int? {
        switch command {
        case .moveForward, .moveRight:
            return 1
        case .moveBackward, .moveLeft:
            return -1
        default:
            return nil
        }
    }

    func roomPath(for roomID: RoomID) -> [GridPosition] {
        switch roomID {
        case .hallway:
            return [
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 4, y: 1),
                GridPosition(x: 5, y: 1),
                GridPosition(x: 6, y: 1)
            ]
        case .bedroom:
            return [
                GridPosition(x: 0, y: 1),
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 3, y: 2),
                GridPosition(x: 4, y: 2),
                GridPosition(x: 5, y: 2),
                GridPosition(x: 6, y: 2),
                GridPosition(x: 6, y: 1)
            ]
        case .livingRoom:
            return [
                GridPosition(x: 0, y: 1),
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 4, y: 1),
                GridPosition(x: 4, y: 2),
                GridPosition(x: 5, y: 1),
                GridPosition(x: 6, y: 1)
            ]
        case .kitchen:
            return [
                GridPosition(x: 0, y: 1),
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 4, y: 1),
                GridPosition(x: 5, y: 1),
                GridPosition(x: 5, y: 2),
                GridPosition(x: 6, y: 1)
            ]
        case .bathroom:
            return [
                GridPosition(x: 0, y: 1),
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 4, y: 1)
            ]
        case .street:
            return [GridPosition(x: 7, y: 14)]
        case .mainStreet:
            return [GridPosition(x: 10, y: 18)]
        }
    }

    func currentLinearRoomIndex(in path: [GridPosition]) -> Int {
        if let exactIndex = path.firstIndex(of: state.player.roomPosition) {
            return exactIndex
        }

        var bestIndex = 0
        var bestDistance = Int.max
        for (index, position) in path.enumerated() {
            let distance = manhattanDistance(from: position, to: state.player.roomPosition)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
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

    func linearIndex(for position: GridPosition) -> Int {
        let x = min(max(0, position.x), currentRoom.width - 1)
        let y = min(max(0, position.y), currentRoom.height - 1)
        return y * currentRoom.width + x
    }

    func position(forWrappedLinearIndex index: Int) -> GridPosition {
        let length = linearTrackLength()
        let normalized = ((index % length) + length) % length
        let x = normalized % currentRoom.width
        let y = normalized / currentRoom.width
        return GridPosition(x: x, y: y)
    }

    func position(forClampedLinearIndex index: Int) -> GridPosition {
        let length = linearTrackLength()
        let normalized = min(max(0, index), length - 1)
        let x = normalized % currentRoom.width
        let y = normalized / currentRoom.width
        return GridPosition(x: x, y: y)
    }
}
