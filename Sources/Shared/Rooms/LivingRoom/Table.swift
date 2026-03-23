import Foundation

enum LivingRoomTable {
    static let itemID = "livingRoom.table"

    enum Stage: String {
        case intact
        case broken
    }

    static func stage(in state: WorldRuntimeState) -> Stage {
        state.itemStage(itemID: itemID, as: Stage.self, default: .intact)
    }

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "стол",
            shortPromptProvider: { state in
                stage(in: state) == .broken ? "Сломанный деревянный стол." : "Деревянный стол."
            },
            fullDescriptionProvider: { state in
                if stage(in: state) == .broken {
                    return "Стол уже разбит. Доски треснули и торчат неровно."
                }
                return "Перед тобой крепкий деревянный стол. По нему можно провести рукой или сильно ударить по краю."
            },
            actionsProvider: { state in
                var actions: [ItemAction] = [
                    ItemAction(trigger: .primary, title: "Потрогать стол", resultText: "Ты провел ладонью по столешнице. Дерево ровное и прохладное.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                ]

                if stage(in: state) == .intact {
                    actions.append(
                        ItemAction(trigger: .force, title: "Разбить стол", resultText: "Ты сильно ударил по столу. Доска треснула и стол перекосился.", sound: .cabinetSmash, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.setItemStage(itemID: itemID, stage: Stage.broken)
                        }
                    )
                }

                return actions
            }
        )
    }
}
