import Foundation

enum GroceryStoreTeabag {
    static let itemID = "groceryStore.teabag"
    static let price = 2

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "пакетик чая",
            shortPromptProvider: { _ in
                "Пакетик чая."
            },
            fullDescriptionProvider: { _ in
                "Чёрный чай в бумажном пакетике. Можно заварить в кружке с кипятком на столике в чайной."
            },
            actionsProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    return [
                        ItemAction(
                            trigger: .describe,
                            title: "Осмотреть пакетик",
                            resultText: "Обычный пакетик чёрного чая. Нужна кружка с кипятком и столик в чайной, чтобы заварить.",
                            sound: nil,
                            requiresHeldItemID: itemID,
                            producesHeldItem: nil
                        ) { _ in },
                        ItemAction(
                            trigger: .throwItem,
                            title: "Бросить пакетик",
                            resultText: "Ты бросил пакетик чая на пол.",
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
                            title: "Взять пакетик чая",
                            resultText: "Ты взял пакетик чая.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: HeldItem(itemID: itemID, name: "пакетик чая")
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
                resultText: "Обычный пакетик чёрного чая. Нужна кружка с кипятком и столик в чайной, чтобы заварить.",
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { _ in },
            ItemAction(
                trigger: .throwItem,
                title: "Бросить пакетик",
                resultText: "Ты бросил пакетик чая на пол.",
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
