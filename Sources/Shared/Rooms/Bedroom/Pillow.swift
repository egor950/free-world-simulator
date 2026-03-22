import Foundation

enum BedroomPillow {
    static let itemID = "bedroom.pillow"
    static let onFloorFlag = "onFloor"
    static let tornFlag = "torn"
    static let dustFlag = "dust"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "подушка",
            shortPromptProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    if state.flag(itemID: itemID, key: tornFlag) {
                        return "В руках порванная подушка."
                    }
                    return "В руках подушка."
                }
                if state.flag(itemID: itemID, key: tornFlag) {
                    return "Порванная подушка."
                }
                if state.flag(itemID: itemID, key: onFloorFlag) {
                    return "Подушка на полу."
                }
                return "Подушка."
            },
            fullDescriptionProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    if state.flag(itemID: itemID, key: tornFlag) {
                        return "У тебя в руках порванная подушка. Из разрыва лезет мягкий наполнитель. Ее можно смять, бросить под ноги или положить куда-нибудь."
                    }
                    if state.flag(itemID: itemID, key: dustFlag) {
                        return "Подушка у тебя в руках. Ты уже выбил из нее немного пыли. Ее можно смять, бросить под ноги, порвать или положить куда-нибудь."
                    }
                    return "Подушка сейчас у тебя в руках. Ее можно смять, бросить под ноги, порвать или положить куда-нибудь."
                }
                if state.flag(itemID: itemID, key: tornFlag) {
                    return "Подушка порвана. Из нее местами торчит мягкий наполнитель."
                }
                if state.flag(itemID: itemID, key: onFloorFlag) {
                    return "Подушка лежит на полу возле кровати. Ее можно поднять."
                }
                return "Подушка лежит на кровати. Ее можно взять или сбросить на пол."
            },
            actionsProvider: { state in
                guard state.player.heldItem == nil else {
                    return []
                }

                let takeText = state.flag(itemID: itemID, key: onFloorFlag)
                    ? "Ты поднял подушку с пола."
                    : "Ты взял подушку с кровати."

                return [
                    ItemAction(trigger: .primary, title: "Взять подушку", resultText: takeText, sound: nil, requiresHeldItemID: nil, producesHeldItem: HeldItem(itemID: itemID, name: "подушка")) { runtimeState in
                        runtimeState.player.heldItem = HeldItem(itemID: itemID, name: "подушка")
                        runtimeState.setFlag(itemID: itemID, key: onFloorFlag, value: false)
                        runtimeState.clearItemLocation(itemID: itemID)
                    },
                    ItemAction(trigger: .throwItem, title: "Сбросить подушку", resultText: "Ты смахнул подушку на пол рядом с кроватью.", sound: .itemPlaceMetal01, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                        runtimeState.setFlag(itemID: itemID, key: onFloorFlag, value: true)
                        runtimeState.setItemLocation(itemID: itemID, roomID: .bedroom, position: GridPosition(x: 4, y: 3))
                    }
                ]
            }
        )
    }

    static func heldActions(for state: WorldRuntimeState) -> [ItemAction] {
        guard state.player.heldItem?.itemID == itemID else { return [] }

        var actions: [ItemAction] = [
            ItemAction(
                trigger: .describe,
                title: "Осмотреть подушку в руках",
                resultText: state.flag(itemID: itemID, key: tornFlag)
                    ? "Подушка порвана, а внутри мягкий наполнитель."
                    : "Ты ощупал подушку в руках. Она мягкая и легкая."
                ,
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { _ in },
            ItemAction(
                trigger: .force,
                title: state.flag(itemID: itemID, key: tornFlag) ? "Трясти порванную подушку" : "Смять подушку",
                resultText: state.flag(itemID: itemID, key: tornFlag)
                    ? "Ты потряс порванную подушку. Наполнитель полез наружу еще сильнее."
                    : "Ты сжал подушку в руках. Она мягко промялась и выпустила немного пыли."
                ,
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.setFlag(itemID: itemID, key: dustFlag, value: true)
            },
            ItemAction(
                trigger: .throwItem,
                title: "Бросить подушку под ноги",
                resultText: "Ты бросил подушку под ноги. Теперь она лежит здесь.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setFlag(itemID: itemID, key: onFloorFlag, value: true)
                runtimeState.setItemLocation(itemID: itemID, roomID: runtimeState.player.roomID, position: runtimeState.player.roomPosition)
            },
            ItemAction(
                trigger: .placeHeldItem,
                title: "Положить подушку рядом",
                resultText: "Ты положил подушку рядом с собой.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setFlag(itemID: itemID, key: onFloorFlag, value: true)
                runtimeState.setItemLocation(itemID: itemID, roomID: runtimeState.player.roomID, position: runtimeState.player.roomPosition)
            }
        ]

        if !state.flag(itemID: itemID, key: tornFlag) {
            actions.append(
                ItemAction(
                    trigger: .primary,
                    title: "Порвать подушку",
                    resultText: "Ты порвал подушку. Изнутри полез мягкий наполнитель.",
                    sound: nil,
                    requiresHeldItemID: itemID,
                    producesHeldItem: nil
                ) { runtimeState in
                    runtimeState.setFlag(itemID: itemID, key: tornFlag, value: true)
                }
            )
        } else {
            actions.append(
                ItemAction(
                    trigger: .primary,
                    title: "Скомкать порванную подушку",
                    resultText: "Ты скомкал порванную подушку в руках. Наполнитель внутри сбился комками.",
                    sound: nil,
                    requiresHeldItemID: itemID,
                    producesHeldItem: nil
                ) { _ in }
            )
        }

        return actions
    }
}
