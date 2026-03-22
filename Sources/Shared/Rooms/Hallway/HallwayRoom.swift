import Foundation

enum HallwayRoom {
    static let neighborDoorID = "hallway.door.neighbors"
    static let neighborDoorNodeID = "hallway.node.neighborsDoor"

    static func make() -> RoomDefinition {
        let coatRack = HallwayCoatRack.make()

        let bedroomDoor = DoorDefinition(id: "hallway.door.bedroom", name: "дверь в спальню", targetRoomID: .bedroom, targetRoomPosition: GridPosition(x: 1, y: 1), state: .closed, focusNodeID: "hallway.node.bedroomDoor", shortPrompt: "Рядом дверь в спальню.", openResultText: "Ты открыл дверь и прошел в спальню.", lockedText: "Заперто.", sound: nil)
        let lockedDoor = DoorDefinition(id: "hallway.door.storage", name: "дверь в кладовку", targetRoomID: .hallway, targetRoomPosition: nil, state: .locked, focusNodeID: "hallway.node.storageDoor", shortPrompt: "Рядом дверь в кладовку.", openResultText: "", lockedText: "Заперто.", sound: nil)
        let neighborDoor = DoorDefinition(id: neighborDoorID, name: "входная дверь", targetRoomID: .hallway, targetRoomPosition: nil, state: .closed, focusNodeID: neighborDoorNodeID, shortPrompt: "У самой двери кто-то зло переминается и ждет, когда ты откроешь.", openResultText: "", lockedText: "Сейчас она не открывается.", sound: nil)

        return RoomDefinition(
            id: .hallway,
            title: "Прихожая",
            entryAnnouncement: "Ты в прихожей.",
            ambientSound: .ambientRoom01,
            width: 7,
            height: 5,
            nodes: [
                FocusNode(id: neighborDoor.focusNodeID, title: neighborDoor.name, position: GridPosition(x: 1, y: 1), target: .door(neighborDoor.id)),
                FocusNode(id: bedroomDoor.focusNodeID, title: bedroomDoor.name, position: GridPosition(x: 6, y: 1), target: .door(bedroomDoor.id)),
                FocusNode(id: coatRack.id, title: coatRack.name, position: GridPosition(x: 3, y: 1), target: .item(coatRack.id)),
                FocusNode(id: lockedDoor.focusNodeID, title: lockedDoor.name, position: GridPosition(x: 0, y: 4), target: .door(lockedDoor.id))
            ],
            doors: [
                neighborDoor.id: neighborDoor,
                bedroomDoor.id: bedroomDoor,
                lockedDoor.id: lockedDoor
            ],
            items: [
                coatRack.id: coatRack
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
