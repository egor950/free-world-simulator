import Foundation

extension GameViewModel {
    var streetCarInteractionDistance: Int { 2 }
    var currentTraversalMode: RoomMovementMode {
        roomTraversalMachine.isGridTraversal ? .freeGrid4Way : .linearPath
    }

    func syncGameplayStateMachines() {
        roomTraversalMachine.sync(mode: currentRoom.movementMode)
        poseMachine.sync(pose: state.player.pose)
        inventoryMachine.sync(isOpen: ui.isInventoryOpen)
    }

    func setPlayerPose(_ pose: PlayerPose) {
        state.player.pose = pose
        poseMachine.sync(pose: pose)
    }

    func setInventoryOpen(_ isOpen: Bool) {
        ui.isInventoryOpen = isOpen
        inventoryMachine.sync(isOpen: isOpen)
    }

    var currentRoom: RoomDefinition {
        rooms[state.player.roomID] ?? rooms[.hallway]!
    }

    func node(for target: FocusTarget) -> FocusNode? {
        switch target {
        case let .door(id):
            return visibleNodes.first { $0.target == .door(id) }
        case let .item(id):
            return visibleNodes.first { $0.target == .item(id) }
        case .none:
            return nil
        }
    }

    func visibleNode(at position: GridPosition) -> FocusNode? {
        visibleNodes.first { $0.position == position }
    }

    func nearbyDoorNode(maxDistance: Int) -> FocusNode? {
        let playerPosition = state.player.roomPosition
        let doorNodes = visibleNodes.filter {
            if case .door = $0.target {
                return true
            }
            return false
        }

        guard let nearest = doorNodes.min(by: {
            manhattanDistance(from: $0.position, to: playerPosition) <
            manhattanDistance(from: $1.position, to: playerPosition)
        }) else {
            return nil
        }

        let distance = manhattanDistance(from: nearest.position, to: playerPosition)
        return distance <= maxDistance ? nearest : nil
    }

    func manhattanDistance(from lhs: GridPosition, to rhs: GridPosition) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }

    func addLog(_ line: String) {
        ui.eventLog.insert(line, at: 0)
        if ui.eventLog.count > 12 {
            ui.eventLog.removeLast()
        }
        onLogLine?(line)
    }

    var isNeighborDoorVisible: Bool {
        (neighborEncounterMachine.isDoorbellRaised || neighborEncounterMachine.isBreakInActive) &&
        !neighborEncounterMachine.isResolved
    }
}
