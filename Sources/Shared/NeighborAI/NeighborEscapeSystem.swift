import Foundation

// MARK: - NeighborEscapeSystem

/// Car escape mechanic: when the neighbor is chasing the player on the street,
/// the player can escape by getting into a parked car.
/// The system is stateless — it only checks conditions and performs the escape action.
@MainActor
final class NeighborEscapeSystem {

    /// Can the player escape via car right now?
    ///
    /// Conditions:
    /// - Player must be on the street (RoomID.street or RoomID.mainStreet)
    /// - Player must NOT already be controlling a car
    /// - There must be at least one parked owned car in the street
    func canPlayerEscape(state: WorldRuntimeState, currentRoom: RoomID) -> Bool {
        guard currentRoom == .street || currentRoom == .mainStreet else { return false }
        guard state.controlledCar == nil else { return false }

        let carsInStreet = state.parkedOwnedCars.values.filter {
            $0.roomID == .street || $0.roomID == .mainStreet
        }
        return !carsInStreet.isEmpty
    }

    /// Attempt to escape via car.
    ///
    /// 1. Finds the nearest parked owned car on the street
    /// 2. Moves the player to the car's grid position
    /// 3. Converts the parked car into a controlled car (engine idle, driving phase)
    /// 4. Returns true on success, false if no car available
    @discardableResult
    func attemptEscape(state: inout WorldRuntimeState) -> Bool {
        let streetCars = state.parkedOwnedCars.values.filter {
            $0.roomID == .street || $0.roomID == .mainStreet
        }
        guard let nearestCar = streetCars.min(by: {
            distanceSquared($0.gridPosition, to: state.player.roomPosition)
                < distanceSquared($1.gridPosition, to: state.player.roomPosition)
        }) else { return false }

        // Teleport player to the car
        state.player.roomPosition = nearestCar.gridPosition

        // Remove from parked owned cars
        state.removeParkedOwnedCar(id: nearestCar.id)

        // Set as controlled car with engine idle, ready to drive
        state.controlledCar = ControlledCarState(
            id: nearestCar.id,
            kind: nearestCar.kind,
            title: nearestCar.title,
            roomID: nearestCar.roomID,
            worldPosition: nearestCar.worldPosition,
            headingRadians: nearestCar.headingRadians,
            speed: 0,
            steeringAxis: 0,
            directionLeftToRight: nearestCar.directionLeftToRight,
            engineState: .running,
            phase: .engineIdle
        )

        return true
    }

    /// Reset — this system is stateless, so this is a no-op.
    func reset() {}

    // MARK: - Private

    private func distanceSquared(_ a: GridPosition, to b: GridPosition) -> Int {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
