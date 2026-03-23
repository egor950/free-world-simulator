import Foundation

enum KitchenFridge {
    static let itemID = "kitchen.fridge"

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
            name: "холодильник",
            shortPromptProvider: { _ in "Холодильник." },
            fullDescriptionProvider: { state in
                if stage(in: state) == .broken {
                    return "Холодильник открыт, а на полу рядом слышны осколки от разбитой бутылки."
                }
                return "Перед тобой холодильник. Его можно открыть, ударить по дверце или смахнуть бутылку с полки."
            },
            actionsProvider: { state in
                var actions: [ItemAction] = [
                    ItemAction(trigger: .primary, title: "Открыть холодильник", resultText: "Ты открыл холодильник. Оттуда тянет холодом, а внутри стоит бутылка воды.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in },
                    ItemAction(trigger: .force, title: "Ударить холодильник", resultText: "Ты стукнул по дверце. Металл гулко отозвался по всей кухне.", sound: .cabinetSmash, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                ]

                if stage(in: state) == .intact {
                    actions.append(
                        ItemAction(trigger: .throwItem, title: "Смахнуть бутылку", resultText: "Ты смахнул бутылку. Она упала и разбилась у холодильника.", sound: .glassBreakSmall, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.setItemStage(itemID: itemID, stage: Stage.broken)
                        }
                    )
                }

                return actions
            }
        )
    }
}
