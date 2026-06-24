import Foundation

struct NeighborStreetChaseSnapshot {
    let roomID: RoomID
    let position: GridPosition
    let distance: Int
    let footstepVolume: Float
}

struct NeighborStreetChaseRuntime {
    private(set) var roomID: RoomID
    private(set) var position: GridPosition
    private var moveAccumulator: TimeInterval = 0
    private var stepSoundAccumulator: TimeInterval = 0
    private var lostSightDuration: TimeInterval = 0

    let catchDistance = 1
    let giveUpDistance = 18
    let giveUpDelay: TimeInterval = 4.0
    let stepInterval: TimeInterval = 0.86
    let stepSoundInterval: TimeInterval = 0.72

    init(playerRoomID: RoomID, playerPosition: GridPosition) {
        roomID = playerRoomID
        position = Self.spawnPosition(for: playerRoomID, playerPosition: playerPosition)
    }

    mutating func tick(
        deltaTime: TimeInterval,
        playerRoomID: RoomID,
        playerPosition: GridPosition,
        roomSize: (width: Int, height: Int)
    ) -> NeighborStreetChaseSnapshot {
        if roomID != playerRoomID {
            roomID = playerRoomID
            position = Self.spawnPosition(for: playerRoomID, playerPosition: playerPosition)
            moveAccumulator = 0
            stepSoundAccumulator = 0
            lostSightDuration = 0
        }

        moveAccumulator += deltaTime
        stepSoundAccumulator += deltaTime

        while moveAccumulator >= stepInterval {
            moveAccumulator -= stepInterval
            position = nextStep(toward: playerPosition, roomSize: roomSize)
        }

        let distance = Self.manhattanDistance(from: position, to: playerPosition)
        if distance >= giveUpDistance {
            lostSightDuration += deltaTime
        } else {
            lostSightDuration = 0
        }

        return NeighborStreetChaseSnapshot(
            roomID: roomID,
            position: position,
            distance: distance,
            footstepVolume: footstepVolume(for: distance)
        )
    }

    mutating func shouldPlayFootstep() -> Bool {
        guard stepSoundAccumulator >= stepSoundInterval else { return false }
        stepSoundAccumulator = 0
        return true
    }

    func hasCaughtPlayer(distance: Int) -> Bool {
        distance <= catchDistance
    }

    func hasLostPlayer() -> Bool {
        lostSightDuration >= giveUpDelay
    }

    private func nextStep(toward target: GridPosition, roomSize: (width: Int, height: Int)) -> GridPosition {
        let dx = target.x - position.x
        let dy = target.y - position.y
        var nextX = position.x
        var nextY = position.y

        if abs(dx) >= abs(dy), dx != 0 {
            nextX += dx > 0 ? 1 : -1
        } else if dy != 0 {
            nextY += dy > 0 ? 1 : -1
        } else if dx != 0 {
            nextX += dx > 0 ? 1 : -1
        }

        return GridPosition(
            x: max(0, min(roomSize.width - 1, nextX)),
            y: max(0, min(roomSize.height - 1, nextY))
        )
    }

    private func footstepVolume(for distance: Int) -> Float {
        let maxAudibleDistance: Float = 16
        let normalizedDistance = min(maxAudibleDistance, Float(max(0, distance)))
        let closeness = 1.0 - (normalizedDistance / maxAudibleDistance)
        return max(0.08, min(1.0, 0.18 + closeness * 0.82))
    }

    private static func spawnPosition(for roomID: RoomID, playerPosition: GridPosition) -> GridPosition {
        switch roomID {
        case .street:
            return StreetRoom.spawnPosition
        case .mainStreet:
            return MainStreetRoom.gatePosition
        default:
            return playerPosition
        }
    }

    private static func manhattanDistance(from lhs: GridPosition, to rhs: GridPosition) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }
}
