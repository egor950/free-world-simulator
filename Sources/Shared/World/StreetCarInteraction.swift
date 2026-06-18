import Foundation

extension GameViewModel {
    func nearestStreetCarGuidance(maxDistance: Int, includeDistance: Bool, parkedOnly: Bool = false) -> String? {
        guard currentRoom.id == .street, !streetCarSnapshots.isEmpty else {
            return nil
        }

        let candidates = parkedOnly ? streetCarSnapshots.filter(\.isParked) : streetCarSnapshots
        guard !candidates.isEmpty else {
            return nil
        }

        let playerPosition = state.player.roomPosition
        guard let nearest = candidates.min(by: {
            manhattanDistance(from: $0.position, to: playerPosition) <
            manhattanDistance(from: $1.position, to: playerPosition)
        }) else {
            return nil
        }

        let distance = manhattanDistance(from: nearest.position, to: playerPosition)
        guard distance > 0, distance <= maxDistance else {
            return nil
        }

        let dx = nearest.position.x - playerPosition.x
        let dy = nearest.position.y - playerPosition.y

        let horizontal: String
        if dx > 0 {
            horizontal = "правее"
        } else if dx < 0 {
            horizontal = "левее"
        } else {
            horizontal = "ровно по линии"
        }

        let vertical: String
        if dy < 0 {
            vertical = "впереди"
        } else if dy > 0 {
            vertical = "позади"
        } else {
            vertical = "на одном уровне"
        }

        if includeDistance {
            return "Ближайшая машина \(vertical), \(horizontal). До нее примерно \(distance) шагов."
        }

        return "Ближайшая машина \(vertical), \(horizontal)."
    }

    func currentFocusStreetCarSnapshot() -> StreetTrafficCoordinator.StreetCarSnapshot? {
        guard state.controlledCar == nil else {
            return nil
        }

        guard let node = currentFocusNode,
              node.id.hasPrefix("street.dynamic.car.") else {
            return nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance)
        }

        let rawID = String(node.id.dropFirst("street.dynamic.car.".count))
        guard let uuid = UUID(uuidString: rawID) else {
            return streetCarSnapshots.first { $0.position == node.position }
                ?? nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance)
        }

        return streetCarSnapshots.first { $0.id == uuid }
            ?? nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance)
    }

    func nearbyParkedStreetCarNode(maxDistance: Int) -> FocusNode? {
        guard state.controlledCar == nil else {
            return nil
        }

        guard let snapshot = nearestParkedStreetCarSnapshot(maxDistance: maxDistance) else {
            return nil
        }

        return FocusNode(
            id: "street.dynamic.car.\(snapshot.id.uuidString)",
            title: snapshot.title,
            position: snapshot.position,
            target: .none,
            shortPrompt: snapshot.shortPrompt,
            fullDescription: snapshot.fullDescription
        )
    }

    func nearestParkedStreetCarSnapshot(maxDistance: Int) -> StreetTrafficCoordinator.StreetCarSnapshot? {
        guard currentRoom.id == .street else {
            return nil
        }

        let playerPosition = state.player.roomPosition
        let parkedCars = streetCarSnapshots.filter(\.isInspectable)
        guard !parkedCars.isEmpty else {
            return nil
        }

        return parkedCars.min(by: {
            manhattanDistance(from: $0.position, to: playerPosition) <
            manhattanDistance(from: $1.position, to: playerPosition)
        }).flatMap { snapshot in
            let distance = manhattanDistance(from: snapshot.position, to: playerPosition)
            return distance <= maxDistance ? snapshot : nil
        }
    }
}
