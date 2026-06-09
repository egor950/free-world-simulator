import Foundation

enum GroceryStoreSugar {
    static let itemID = "groceryStore.sugar"
    static let price = 1

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "пакетик сахара",
            shortPromptProvider: { _ in
                "Пакетик сахара."
            },
            fullDescriptionProvider: { _ in
                "Маленький пакетик сахарного песка. Можно добавить в готовый чай на столике в чайной."
            },
            actionsProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    return [
                        ItemAction(
                            trigger: .describe,
                            title: "Осмотреть пакетик",
                            resultText: "Пакетик сахара. Добавь в готовый чай на столике в чайной.",
                            sound: nil,
                            requiresHeldItemID: itemID,
                            producesHeldItem: nil
                        ) { _ in },
                        ItemAction(
                            trigger: .throwItem,
                            title: "Бросить пакетик",
                            resultText: "Ты бросил пакетик сахара на пол.",
                            sound: .itemPlaceMetal01,
                            requiresHeldItemID: itemID,
                            producesHeldItem: nil
                        ) { runtimeState in
                            runtimeState.player.heldItem = nil
                            runtimeState.setItemLocation(
                                itemID: itemID,
                                roomID: runtimeState.player.roomID,
                                position: runtimeState.player.roomPosition
                            )
                        }
                    ]
                }

                if state.player.heldItem == nil {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Взять пакетик сахара",
                            resultText: "Ты взял пакетик сахара.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: HeldItem(itemID: itemID, name: "пакетик сахара")
                        ) { runtimeState in
                            runtimeState.clearItemLocation(itemID: itemID)
                        }
                    ]
                }

                return []
            }
        )
    }

    static func heldActions(for state: WorldRuntimeState) -> [ItemAction] {
        guard state.player.heldItem?.itemID == itemID else { return [] }

        return [
            ItemAction(
                trigger: .describe,
                title: "Осмотреть пакетик",
                resultText: "Пакетик сахара. Добавь в готовый чай на столике в чайной.",
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { _ in },
            ItemAction(
                trigger: .throwItem,
                title: "Бросить пакетик",
                resultText: "Ты бросил пакетик сахара на пол.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setItemLocation(
                    itemID: itemID,
                    roomID: runtimeState.player.roomID,
                    position: runtimeState.player.roomPosition
                )
            }
        ]
    }
}
