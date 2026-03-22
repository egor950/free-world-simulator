import Foundation

enum BedroomBed {
    static let itemID = "bedroom.bed"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "кровать",
            shortPromptProvider: { _ in "Кровать." },
            fullDescriptionProvider: { state in
                let base = "Перед тобой кровать с мягким матрасом."
                let poseText: String
                if state.player.pose == .standing {
                    poseText = "Сейчас ты стоишь рядом с кроватью."
                } else {
                    poseText = "Сейчас ты находишься на кровати."
                }
                let pillowText: String
                if state.player.heldItem?.itemID == BedroomPillow.itemID {
                    pillowText = "Подушка у тебя в руках."
                } else if state.flag(itemID: BedroomPillow.itemID, key: BedroomPillow.onFloorFlag) {
                    pillowText = "Подушка лежит на полу рядом."
                } else {
                    pillowText = "Подушка лежит на кровати."
                }
                return [base, poseText, pillowText].joined(separator: " ")
            },
            actionsProvider: { state in
                var actions: [ItemAction] = []

                if state.player.pose != .standing {
                    actions.append(
                        ItemAction(trigger: .primary, title: "Встать с кровати", resultText: "Ты аккуратно встал с кровати.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.player.pose = .standing
                        }
                    )
                } else {
                    actions.append(
                        ItemAction(trigger: .primary, title: "Лечь на кровать", resultText: "Ты лег на кровать. Матрас мягко прогнулся под тобой.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.player.pose = .lying
                        }
                    )
                }

                actions.append(
                    ItemAction(trigger: .force, title: "Ударить по кровати", resultText: "Ты ударил по матрасу. Он глухо отозвался под рукой.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                )

                if state.player.heldItem?.itemID == BedroomPillow.itemID {
                    actions.append(
                        ItemAction(trigger: .placeHeldItem, title: "Положить подушку", resultText: "Ты положил подушку обратно на кровать.", sound: .itemPlaceMetal01, requiresHeldItemID: BedroomPillow.itemID, producesHeldItem: nil) { runtimeState in
                            runtimeState.player.heldItem = nil
                            runtimeState.setFlag(itemID: BedroomPillow.itemID, key: BedroomPillow.onFloorFlag, value: false)
                            runtimeState.clearItemLocation(itemID: BedroomPillow.itemID)
                        }
                    )
                }

                if state.player.heldItem == nil && !state.flag(itemID: BedroomPillow.itemID, key: BedroomPillow.onFloorFlag) {
                    actions.append(
                        ItemAction(trigger: .throwItem, title: "Сбросить подушку", resultText: "Ты сбросил подушку с кровати на пол.", sound: .itemPlaceMetal01, requiresHeldItemID: nil, producesHeldItem: nil) { runtimeState in
                            runtimeState.setFlag(itemID: BedroomPillow.itemID, key: BedroomPillow.onFloorFlag, value: true)
                            runtimeState.setItemLocation(itemID: BedroomPillow.itemID, roomID: .bedroom, position: GridPosition(x: 4, y: 3))
                        }
                    )
                }

                return actions
            }
        )
    }
}
