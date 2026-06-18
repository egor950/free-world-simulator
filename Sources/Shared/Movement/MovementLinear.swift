import Foundation

extension GameViewModel {
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
            announceMovementNode(node)
        } else {
            setSilentStatus("Ты двигаешься дальше по комнате.")
        }
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
                GridPosition(x: 4, y: 2),
                GridPosition(x: 5, y: 2),
                GridPosition(x: 5, y: 1),
                GridPosition(x: 6, y: 1)
            ]
        case .bathroom:
            return [
                GridPosition(x: 0, y: 1),
                GridPosition(x: 1, y: 1),
                GridPosition(x: 2, y: 1),
                GridPosition(x: 3, y: 1),
                GridPosition(x: 4, y: 1),
                GridPosition(x: 5, y: 1)
            ]
        case .teaRoom:
            return (0...19).map { GridPosition(x: $0, y: 1) }
        case .street:
            return [GridPosition(x: 7, y: 14)]
        case .mainStreet:
            return [MainStreetRoom.gatePosition]
        case .groceryStore:
            return [GroceryStoreRoom.entryPosition]
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
}
