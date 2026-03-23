import Foundation

enum MainStreetRoom {
    static let gateDoorID = "mainStreet.gate.street"

    static func make() -> RoomDefinition {
        let gateDoor = DoorDefinition(
            id: gateDoorID,
            name: "калитка",
            targetRoomID: .street,
            targetRoomPosition: GridPosition(x: 7, y: 0),
            state: .closed,
            focusNodeID: "mainStreet.node.gate",
            shortPrompt: "Позади калитка обратно во двор.",
            openResultText: "Ты открыл калитку и можешь вернуться во двор.",
            lockedText: "Калитка не поддается.",
            sound: nil,
            interactionStyle: .timedGate(StreetRoom.gateTiming)
        )

        return RoomDefinition(
            id: .mainStreet,
            title: "Улица",
            entryAnnouncement: "Ты вышел дальше на улицу. Здесь просторнее, шире и тише, чем во дворе, а вокруг открытое пространство.",
            ambientSound: nil,
            movementMode: .freeGrid4Way,
            stepSurface: .asphalt,
            width: 21,
            height: 19,
            nodes: [
                FocusNode(
                    id: gateDoor.focusNodeID,
                    title: gateDoor.name,
                    position: GridPosition(x: 10, y: 18),
                    target: .door(gateDoor.id),
                    shortPrompt: "Позади калитка обратно во двор. Если она открыта, нажми назад, чтобы вернуться.",
                    fullDescription: "Позади тебя калитка обратно во двор. Через нее можно вернуться к дому и парковке."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.center",
                    title: "широкий асфальт улицы",
                    position: GridPosition(x: 10, y: 9),
                    fullDescription: "Ты почти в середине широкой улицы. Под ногами открытый асфальт, рядом больше воздуха и пространства."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.forward",
                    title: "дальний край улицы",
                    position: GridPosition(x: 10, y: 0),
                    fullDescription: "Ты дошел до дальнего края этой улицы. Дальше путь пока еще не сделан."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.left",
                    title: "левый край улицы",
                    position: GridPosition(x: 0, y: 9),
                    fullDescription: "Ты у левого края широкой улицы. Дальше влево пока ничего нет."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.right",
                    title: "правый край улицы",
                    position: GridPosition(x: 20, y: 9),
                    fullDescription: "Ты у правого края широкой улицы. Дальше вправо путь пока закрыт."
                )
            ],
            doors: [
                gateDoor.id: gateDoor
            ],
            items: [:],
            spawnPosition: GridPosition(x: 10, y: 18)
        )
    }
}
