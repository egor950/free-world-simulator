import Foundation

struct PlayerState {
    var roomID: RoomID
    var roomPosition: GridPosition
    var focusedTarget: FocusTarget
    var pose: PlayerPose
    var heldItem: HeldItem?
    var hasCompletedTutorial: Bool
    var coins: Int = 0
}

struct WorldRuntimeState {
    var player: PlayerState
    var controlledCar: ControlledCarState?
    var parkedOwnedCars: [UUID: ParkedOwnedCarState] = [:]
    private(set) var itemStages: [String: String] = [:]
    private(set) var itemPositions: [String: GridPosition] = [:]
    private(set) var itemRooms: [String: RoomID] = [:]

    func itemStage<Stage: RawRepresentable>(
        itemID: String,
        as type: Stage.Type,
        default defaultValue: Stage
    ) -> Stage where Stage.RawValue == String {
        guard let rawValue = itemStages[itemID],
              let stage = Stage(rawValue: rawValue) else {
            return defaultValue
        }

        return stage
    }

    mutating func setItemStage<Stage: RawRepresentable>(
        itemID: String,
        stage: Stage?
    ) where Stage.RawValue == String {
        itemStages[itemID] = stage?.rawValue
    }

    mutating func setRawItemStage(itemID: String, rawValue: String?) {
        itemStages[itemID] = rawValue
    }

    func position(for itemID: String) -> GridPosition? {
        itemPositions[itemID]
    }

    func room(for itemID: String) -> RoomID? {
        itemRooms[itemID]
    }

    var locatedItemIDs: [String] {
        Array(itemRooms.keys)
    }

    mutating func setItemLocation(itemID: String, roomID: RoomID, position: GridPosition) {
        itemRooms[itemID] = roomID
        itemPositions[itemID] = position
    }

    mutating func clearItemLocation(itemID: String) {
        itemRooms[itemID] = nil
        itemPositions[itemID] = nil
    }

    mutating func setParkedOwnedCar(_ car: ParkedOwnedCarState) {
        parkedOwnedCars[car.id] = car
    }

    mutating func removeParkedOwnedCar(id: UUID) {
        parkedOwnedCars[id] = nil
    }
}
