import Foundation

enum LivingRoomTable {
    static let itemID = "livingRoom.table"
    static let brokenFlag = "broken"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "стол",
            shortPromptProvider: { state in
                state.flag(itemID: itemID, key: brokenFlag) ? "Сломанный деревянный стол." : "Деревянный стол."
            },
            fullDescriptionProvider: { state in
                if state.flag(itemID: itemID, key: brokenFlag) {
                    return "Стол уже разбит. Доски треснули и торчат неровно."
                }
                return "Перед тобой крепкий деревянный стол. По нему можно провести рукой или сильно ударить по краю."
            },
            actionsProvider: { state in
                var actions: [ItemAction] = [
                    ItemAction(trigger: .primary, title: "Потрогать стол", resultText: "Ты провел ладонью по столешнице. Дерево ровное и прохладное.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                ]

                if !state.flag(itemID: itemID, key: brokenFlag) {
                    actions.append(
                        ItemAction(trigger: .force, title: "Разбить стол", resultText: "Ты сильно ударил по столу. Доска треснула и стол перекосился.", sound: .cabinetSmash, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.setFlag(itemID: itemID, key: brokenFlag, value: true)
                        }
                    )
                }

                return actions
            }
        )
    }
}
