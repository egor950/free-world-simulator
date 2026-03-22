import Foundation

enum WorldBuilder {
    static func makeWorld() -> [RoomID: RoomDefinition] {
        let rooms = [
            HallwayRoom.make(),
            BedroomRoom.make(),
            LivingRoomRoom.make(),
            KitchenRoom.make(),
            BathroomRoom.make(),
            StreetRoom.make()
        ]

        return Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
    }
}

enum StreetRoom {
    static let apartmentDoorID = "street.door.apartment"

    static func make() -> RoomDefinition {
        let apartmentDoor = DoorDefinition(
            id: apartmentDoorID,
            name: "дверь обратно в квартиру",
            targetRoomID: .bathroom,
            targetRoomPosition: GridPosition(x: 4, y: 1),
            state: .closed,
            focusNodeID: "street.node.apartmentDoor",
            shortPrompt: "Рядом дверь обратно в квартиру.",
            openResultText: "Ты открыл дверь и можешь вернуться в ванную.",
            lockedText: "Заперто.",
            sound: nil
        )

        return RoomDefinition(
            id: .street,
            title: "Улица",
            entryAnnouncement: "Ты вышел во двор. Здесь можно идти во все четыре стороны. Под ногами асфальт.",
            ambientSound: nil,
            movementMode: .freeGrid4Way,
            stepSurface: .asphalt,
            width: 15,
            height: 15,
            nodes: [
                FocusNode(
                    id: apartmentDoor.focusNodeID,
                    title: apartmentDoor.name,
                    position: GridPosition(x: 7, y: 14),
                    target: .door(apartmentDoor.id),
                    shortPrompt: "Позади тебя вход обратно в квартиру. Если дверь открыта, нажми назад, чтобы войти.",
                    fullDescription: "Перед тобой дверь обратно в квартиру. За ней ванная и вся квартира."
                ),
                FocusNode.floor(
                    id: "street.node.center",
                    title: "асфальт двора",
                    position: GridPosition(x: 7, y: 7),
                    fullDescription: "Ты стоишь почти в центре двора. Под ногами жесткий асфальт, а вокруг открытое пространство."
                ),
                FocusNode.floor(
                    id: "street.node.road",
                    title: "край дороги",
                    position: GridPosition(x: 7, y: 0),
                    fullDescription: "Здесь уже самый край дороги. Впереди поток машин, дальше идти нельзя."
                ),
                FocusNode.floor(
                    id: "street.node.wall",
                    title: "стена дома",
                    position: GridPosition(x: 0, y: 7),
                    fullDescription: "Слева тянется стена дома. Она держит двор, и дальше прохода нет."
                ),
                FocusNode.floor(
                    id: "street.node.edge",
                    title: "край двора",
                    position: GridPosition(x: 14, y: 7),
                    fullDescription: "Ты дошел до правого края двора. Дальше путь пока закрыт."
                )
            ],
            doors: [
                apartmentDoor.id: apartmentDoor
            ],
            items: [:],
            spawnPosition: GridPosition(x: 7, y: 14)
        )
    }
}
