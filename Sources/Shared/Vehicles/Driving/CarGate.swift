import Foundation

extension GameViewModel {
    func currentGateIsOpen() -> Bool {
        let gateDoor = rooms[.street]?.doors[StreetRoom.gateDoorID]
        return gateDoor.map { timedDoorConfiguration(for: $0) != nil ? gateMachine(for: $0).isOpen : isDoorOpened($0) } ?? false
    }

    func shouldAutoPassGate(for car: ControlledCarState) -> Bool {
        guard car.speed > 0.18 else { return false }

        if car.roomID == .street {
            return car.worldPosition.z >= 15.8 &&
                car.worldPosition.z <= 23.2 &&
                abs(car.worldPosition.x) <= 12.5
        }

        if car.roomID == .mainStreet {
            return car.worldPosition.z >= 17.2 &&
                car.worldPosition.z <= 26.8 &&
                abs(car.worldPosition.x) <= 12.5
        }

        return false
    }
}
