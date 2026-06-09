import Foundation

enum GroceryStoreRoom {
    static let streetDoorID = "groceryStore.door.mainStreet"
    static let clerkItemID = "groceryStore.clerk"
    static let mugShelfItemID = "groceryStore.mugShelf"
    static let goodsShelfItemID = "groceryStore.goodsShelf"

    static let width = 15
    static let height = 9
    static let entryPosition = GridPosition(x: 0, y: 4)
    static let counterPosition = GridPosition(x: 7, y: 4)

    static let listGoodsInteractionID = "groceryStore.listGoods"
    static let askForMugInteractionID = "groceryStore.askForMug"
    static let askFreebieInteractionID = "groceryStore.askFreebie"
    static let askWaterInteractionID = "groceryStore.askWater"
    static let takeShelfMugInteractionID = "groceryStore.takeShelfMug"
    static let buyTeabagInteractionID = "groceryStore.buyTeabag"
    static let buySugarInteractionID = "groceryStore.buySugar"

    static func make() -> RoomDefinition {
        let streetDoor = DoorDefinition(
            id: streetDoorID,
            name: "дверь на улицу",
            targetRoomID: .mainStreet,
            targetRoomPosition: MainStreetRoom.groceryDoorPosition,
            state: .closed,
            focusNodeID: "groceryStore.node.streetDoor",
            shortPrompt: "Слева дверь обратно на большую улицу.",
            openResultText: "Ты открыл дверь и можешь выйти обратно на улицу.",
            lockedText: "Дверь не открывается.",
            sound: nil
        )
        let clerk = makeClerk()
        let mugShelf = makeMugShelf()
        let goodsShelf = makeGoodsShelf()

        return RoomDefinition(
            id: .groceryStore,
            title: "Продуктовый",
            entryAnnouncement: "Ты вошел в большой продуктовый. Слева дверь обратно на улицу, впереди прилавок с продавцом, а дальше полки с товарами и кружками.",
            ambientSound: .ambientRoom01,
            movementMode: .freeGrid4Way,
            width: width,
            height: height,
            nodes: [
                FocusNode(
                    id: streetDoor.focusNodeID,
                    title: streetDoor.name,
                    position: entryPosition,
                    target: .door(streetDoor.id),
                    shortPrompt: "Слева дверь обратно на улицу. Если она открыта, нажми влево, чтобы выйти.",
                    fullDescription: "Позади тебя дверь обратно на большую улицу. Через нее можно выйти к длинному фасаду магазина."
                ),
                FocusNode(
                    id: clerk.id,
                    title: clerk.name,
                    position: counterPosition,
                    target: .item(clerk.id)
                ),
                FocusNode(
                    id: mugShelf.id,
                    title: mugShelf.name,
                    position: GridPosition(x: 10, y: 2),
                    target: .item(mugShelf.id)
                ),
                FocusNode(
                    id: goodsShelf.id,
                    title: goodsShelf.name,
                    position: GridPosition(x: 11, y: 5),
                    target: .item(goodsShelf.id)
                ),
                FocusNode.floor(
                    id: "groceryStore.node.center",
                    title: "проход между полками",
                    position: GridPosition(x: 4, y: 4),
                    fullDescription: "Ты стоишь в проходе магазина. Впереди продавец, справа полки, а слева выход обратно на улицу."
                )
            ],
            doors: [
                streetDoor.id: streetDoor
            ],
            items: [
                clerk.id: clerk,
                mugShelf.id: mugShelf,
                goodsShelf.id: goodsShelf
            ],
            spawnPosition: GridPosition(x: 1, y: 4)
        )
    }

    private static func makeClerk() -> ItemDefinition {
        ItemDefinition(
            id: clerkItemID,
            name: "продавец",
            shortPromptProvider: { _ in
                "За прилавком продавец. Можно спросить, что у него есть, попросить кружку или купить чай и сахар."
            },
            fullDescriptionProvider: { _ in
                "Перед тобой продавец за длинным прилавком. Он спокойно ждет вопроса и явно привык, что к нему подходят за мелочами. На ценнике: пакетик чая — 2 монеты, сахар — 1 монета."
            },
            actionsProvider: { _ in
                [
                    ItemAction(
                        trigger: .primary,
                        title: "Что у вас есть?",
                        resultText: "",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil,
                        interactionID: GroceryStoreRoom.listGoodsInteractionID
                    ) { _ in },
                    ItemAction(
                        trigger: .force,
                        title: "Дайте пустую кружку",
                        resultText: "",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil,
                        interactionID: GroceryStoreRoom.askForMugInteractionID
                    ) { _ in },
                    ItemAction(
                        trigger: .throwItem,
                        title: "Купить пакетик чая — \(GroceryStoreTeabag.price) монеты",
                        resultText: "",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil,
                        interactionID: GroceryStoreRoom.buyTeabagInteractionID
                    ) { _ in },
                    ItemAction(
                        trigger: .placeHeldItem,
                        title: "Купить сахар — \(GroceryStoreSugar.price) монета",
                        resultText: "",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil,
                        interactionID: GroceryStoreRoom.buySugarInteractionID
                    ) { _ in }
                ]
            }
        )
    }

    private static func makeMugShelf() -> ItemDefinition {
        ItemDefinition(
            id: mugShelfItemID,
            name: "полка с кружками",
            shortPromptProvider: { _ in
                "Справа полка с пустыми кружками."
            },
            fullDescriptionProvider: { _ in
                "На полке аккуратно стоят пустые кружки. Похоже, отсюда можно спокойно взять еще одну."
            },
            actionsProvider: { _ in
                [
                    ItemAction(
                        trigger: .primary,
                        title: "Взять пустую кружку",
                        resultText: "",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil,
                        interactionID: takeShelfMugInteractionID
                    ) { _ in },
                    ItemAction(
                        trigger: .force,
                        title: "Посмотреть кружки",
                        resultText: "На полке стоят пустые кружки. Они простые, крепкие и как раз подходят, чтобы таскать домой кипяток.",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil
                    ) { _ in }
                ]
            }
        )
    }

    private static func makeGoodsShelf() -> ItemDefinition {
        ItemDefinition(
            id: goodsShelfItemID,
            name: "полка с товарами",
            shortPromptProvider: { _ in
                "Рядом полка с водой, хлебом и мелочами."
            },
            fullDescriptionProvider: { _ in
                "На полке стоят бутылки воды, хлеб, печенье и всякая простая мелочь. Пока это скорее фон магазина, чем настоящая экономика."
            },
            actionsProvider: { _ in
                [
                    ItemAction(
                        trigger: .primary,
                        title: "Осмотреть товары",
                        resultText: "Ты быстро ощупал полку. Здесь вода, хлеб, печенье и всякая магазинная бытовая мелочь.",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil
                    ) { _ in },
                    ItemAction(
                        trigger: .force,
                        title: "Спросить про воду",
                        resultText: "",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil,
                        interactionID: askWaterInteractionID
                    ) { _ in }
                ]
            }
        )
    }
}
