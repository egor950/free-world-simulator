import Foundation

enum BathroomMirror {
    static let itemID = "bathroom.mirror"
    static let brokenFlag = "broken"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "зеркало",
            shortPromptProvider: { state in
                state.flag(itemID: itemID, key: brokenFlag) ? "Разбитое зеркало." : "Зеркало."
            },
            fullDescriptionProvider: { state in
                if state.flag(itemID: itemID, key: brokenFlag) {
                    return "Зеркало разбито. По краям остались острые куски стекла."
                }
                return "Перед тобой зеркало над раковиной. Его можно потрогать или разбить."
            },
            actionsProvider: { state in
                var actions: [ItemAction] = [
                    ItemAction(trigger: .primary, title: "Коснуться зеркала", resultText: "Ты коснулся холодной гладкой поверхности зеркала.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                ]

                if !state.flag(itemID: itemID, key: brokenFlag) {
                    actions.append(
                        ItemAction(trigger: .force, title: "Разбить зеркало", resultText: "Ты ударил по зеркалу. Оно треснуло и рассыпалось мелким стеклом.", sound: .glassBreakSmall, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.setFlag(itemID: itemID, key: brokenFlag, value: true)
                        }
                    )
                }

                return actions
            }
        )
    }
}
