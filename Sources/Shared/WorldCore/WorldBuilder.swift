import Foundation

enum WorldBuilder {
    static func makeWorld() -> [RoomID: RoomDefinition] {
        let rooms = [
            HallwayRoom.make(),
            BedroomRoom.make(),
            LivingRoomRoom.make(),
            KitchenRoom.make(),
            BathroomRoom.make(),
            StreetRoom.make(),
            MainStreetRoom.make()
        ]

        return Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
    }
}

enum StreetRoom {
    static let apartmentDoorID = "street.door.apartment"
    static let gateDoorID = "street.gate.mainStreet"

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
        let gateDoor = DoorDefinition(
            id: gateDoorID,
            name: "калитка",
            targetRoomID: .mainStreet,
            targetRoomPosition: GridPosition(x: 10, y: 18),
            state: .closed,
            focusNodeID: "street.node.gate",
            shortPrompt: "Впереди калитка на большую улицу.",
            openResultText: "Ты открыл калитку и можешь выйти дальше на улицу.",
            lockedText: "Калитка не поддается.",
            sound: nil
        )

        return RoomDefinition(
            id: .street,
            title: "Улица",
            entryAnnouncement: "Ты вышел на улицу. Здесь пока двор, и можно идти во все четыре стороны. Под ногами асфальт.",
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
                FocusNode(
                    id: gateDoor.focusNodeID,
                    title: gateDoor.name,
                    position: GridPosition(x: 7, y: 0),
                    target: .door(gateDoor.id),
                    shortPrompt: "Впереди калитка. Если она открыта, нажми вперед, чтобы выйти дальше на улицу.",
                    fullDescription: "Перед тобой калитка. За ней идет более широкая улица."
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
                apartmentDoor.id: apartmentDoor,
                gateDoor.id: gateDoor
            ],
            items: [:],
            spawnPosition: GridPosition(x: 7, y: 14)
        )
    }
}

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
            sound: nil
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
