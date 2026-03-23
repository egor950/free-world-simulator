import Foundation

enum BathroomMirror {
    static let itemID = "bathroom.mirror"

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
            name: "зеркало",
            shortPromptProvider: { state in
                stage(in: state) == .broken ? "Разбитое зеркало." : "Зеркало."
            },
            fullDescriptionProvider: { state in
                if stage(in: state) == .broken {
                    return "Зеркало разбито. По краям остались острые куски стекла."
                }
                return "Перед тобой зеркало над раковиной. Его можно потрогать или разбить."
            },
            actionsProvider: { state in
                var actions: [ItemAction] = [
                    ItemAction(trigger: .primary, title: "Коснуться зеркала", resultText: "Ты коснулся холодной гладкой поверхности зеркала.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                ]

                if stage(in: state) == .intact {
                    actions.append(
                        ItemAction(trigger: .force, title: "Разбить зеркало", resultText: "Ты ударил по зеркалу. Оно треснуло и рассыпалось мелким стеклом.", sound: .glassBreakSmall, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.setItemStage(itemID: itemID, stage: Stage.broken)
                        }
                    )
                }

                return actions
            }
        )
    }
}
