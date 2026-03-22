import Foundation

enum BathroomRoom {
    static func make() -> RoomDefinition {
        let mirror = BathroomMirror.make()
        let kitchenDoor = DoorDefinition(id: "bathroom.door.kitchen", name: "дверь на кухню", targetRoomID: .kitchen, targetRoomPosition: GridPosition(x: 5, y: 1), state: .closed, focusNodeID: "bathroom.node.kitchenDoor", shortPrompt: "Рядом дверь на кухню.", openResultText: "Ты открыл дверь и вернулся на кухню.", lockedText: "Заперто.", sound: nil)
        let streetDoor = DoorDefinition(id: "bathroom.door.street", name: "дверь на улицу", targetRoomID: .street, targetRoomPosition: nil, state: .closed, focusNodeID: "bathroom.node.streetDoor", shortPrompt: "Рядом дверь на улицу.", openResultText: "Ты открыл дверь и вышел на улицу.", lockedText: "Заперто.", sound: nil)

        return RoomDefinition(
            id: .bathroom,
            title: "Ванная",
            entryAnnouncement: "Ты в ванной.",
            ambientSound: .ambientRoom01,
            width: 5,
            height: 4,
            nodes: [
                FocusNode(id: kitchenDoor.focusNodeID, title: kitchenDoor.name, position: GridPosition(x: 0, y: 1), target: .door(kitchenDoor.id)),
                FocusNode(id: mirror.id, title: mirror.name, position: GridPosition(x: 3, y: 1), target: .item(mirror.id)),
                FocusNode(id: streetDoor.focusNodeID, title: streetDoor.name, position: GridPosition(x: 4, y: 1), target: .door(streetDoor.id))
            ],
            doors: [
                kitchenDoor.id: kitchenDoor,
                streetDoor.id: streetDoor
            ],
            items: [
                mirror.id: mirror
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
