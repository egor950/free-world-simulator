import Foundation

enum BedroomRoom {
    static func make() -> RoomDefinition {
        let bed = BedroomBed.make()
        let pillow = BedroomPillow.make()
        let hallwayDoor = DoorDefinition(id: "bedroom.door.hallway", name: "дверь в прихожую", targetRoomID: .hallway, targetRoomPosition: GridPosition(x: 5, y: 1), state: .closed, focusNodeID: "bedroom.node.hallwayDoor", shortPrompt: "Рядом дверь в прихожую.", openResultText: "Ты открыл дверь и вышел в прихожую.", lockedText: "Заперто.", sound: nil)
        let livingDoor = DoorDefinition(id: "bedroom.door.livingRoom", name: "дверь в гостиную", targetRoomID: .livingRoom, targetRoomPosition: GridPosition(x: 1, y: 1), state: .closed, focusNodeID: "bedroom.node.livingDoor", shortPrompt: "Рядом дверь в гостиную.", openResultText: "Ты открыл дверь и вошел в гостиную.", lockedText: "Заперто.", sound: nil)

        return RoomDefinition(
            id: .bedroom,
            title: "Спальня",
            entryAnnouncement: "Ты в спальне.",
            ambientSound: .ambientRoom01,
            width: 7,
            height: 5,
            nodes: [
                FocusNode(id: hallwayDoor.focusNodeID, title: hallwayDoor.name, position: GridPosition(x: 0, y: 1), target: .door(hallwayDoor.id)),
                FocusNode(id: livingDoor.focusNodeID, title: livingDoor.name, position: GridPosition(x: 6, y: 1), target: .door(livingDoor.id)),
                FocusNode(id: bed.id, title: bed.name, position: GridPosition(x: 3, y: 2), target: .item(bed.id)),
                FocusNode(id: pillow.id, title: pillow.name, position: GridPosition(x: 4, y: 2), target: .item(pillow.id))
            ],
            doors: [
                hallwayDoor.id: hallwayDoor,
                livingDoor.id: livingDoor
            ],
            items: [
                bed.id: bed,
                pillow.id: pillow
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
