import Foundation

enum LivingRoomGlassTV {
    static let itemID = "livingRoom.glassTV"
    static let brokenFlag = "broken"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "стеклянный телевизор",
            shortPromptProvider: { state in
                state.flag(itemID: itemID, key: brokenFlag)
                    ? "Большой разбитый телевизор."
                    : "Большой стеклянный телевизор."
            },
            fullDescriptionProvider: { state in
                if state.flag(itemID: itemID, key: brokenFlag) {
                    return "Большой телевизор уже разбит. Под ним хрустят крупные стеклянные осколки."
                }

                return "Перед тобой большой стеклянный телевизор в гостиной. Он гладкий, тяжелый и явно не переживет хороший удар."
            },
            actionsProvider: { state in
                var actions: [ItemAction] = [
                    ItemAction(
                        trigger: .primary,
                        title: "Потрогать телевизор",
                        resultText: "Ты провел рукой по холодному экрану телевизора.",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil
                    ) { _ in }
                ]

                if !state.flag(itemID: itemID, key: brokenFlag) {
                    actions.append(
                        ItemAction(
                            trigger: .force,
                            title: "Разбить телевизор",
                            resultText: "Ты врезал по телевизору. Экран с треском лопнул, и по гостиной разлетелось стекло.",
                            sound: .glassBreakSmall,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { runtimeState in
                            runtimeState.setFlag(itemID: itemID, key: brokenFlag, value: true)
                        }
                    )
                }

                return actions
            }
        )
    }
}

enum LivingRoomRoom {
    static func make() -> RoomDefinition {
        let table = LivingRoomTable.make()
        let glassTV = LivingRoomGlassTV.make()
        let bedroomDoor = DoorDefinition(id: "livingRoom.door.bedroom", name: "дверь в спальню", targetRoomID: .bedroom, targetRoomPosition: GridPosition(x: 5, y: 1), state: .closed, focusNodeID: "livingRoom.node.bedroomDoor", shortPrompt: "Рядом дверь в спальню.", openResultText: "Ты открыл дверь и вернулся в спальню.", lockedText: "Заперто.", sound: nil)
        let kitchenDoor = DoorDefinition(id: "livingRoom.door.kitchen", name: "дверь на кухню", targetRoomID: .kitchen, targetRoomPosition: GridPosition(x: 1, y: 1), state: .closed, focusNodeID: "livingRoom.node.kitchenDoor", shortPrompt: "Рядом дверь на кухню.", openResultText: "Ты открыл дверь и вошел на кухню.", lockedText: "Заперто.", sound: nil)

        return RoomDefinition(
            id: .livingRoom,
            title: "Гостиная",
            entryAnnouncement: "Ты в гостиной.",
            ambientSound: .ambientRoom01,
            width: 7,
            height: 5,
            nodes: [
                FocusNode(id: bedroomDoor.focusNodeID, title: bedroomDoor.name, position: GridPosition(x: 0, y: 1), target: .door(bedroomDoor.id)),
                FocusNode(id: kitchenDoor.focusNodeID, title: kitchenDoor.name, position: GridPosition(x: 6, y: 1), target: .door(kitchenDoor.id)),
                FocusNode(id: glassTV.id, title: glassTV.name, position: GridPosition(x: 4, y: 1), target: .item(glassTV.id)),
                FocusNode(id: table.id, title: table.name, position: GridPosition(x: 4, y: 2), target: .item(table.id))
            ],
            doors: [
                bedroomDoor.id: bedroomDoor,
                kitchenDoor.id: kitchenDoor
            ],
            items: [
                glassTV.id: glassTV,
                table.id: table
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
