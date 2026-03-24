import Foundation

enum KitchenMug {
    static let itemID = "kitchen.mug"

    enum FillState: String {
        case empty
        case filledHotWater
    }

    static func fillState(in state: WorldRuntimeState) -> FillState {
        state.itemStage(itemID: itemID, as: FillState.self, default: .empty)
    }

    static func setFillState(_ value: FillState, in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: itemID, stage: value)
    }

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "кружка",
            shortPromptProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    return fillState(in: state) == .filledHotWater ? "В руках кружка с горячей водой." : "В руках пустая кружка."
                }
                return fillState(in: state) == .filledHotWater ? "Кружка с горячей водой." : "Пустая кружка."
            },
            fullDescriptionProvider: { state in
                let contentText = fillState(in: state) == .filledHotWater
                    ? "Внутри горячая вода."
                    : "Пока она пустая."

                if state.player.heldItem?.itemID == itemID {
                    return "У тебя в руках кружка. \(contentText)"
                }

                return "Перед тобой кружка. \(contentText)"
            },
            actionsProvider: { state in
                if state.player.heldItem?.itemID == KitchenKettle.itemID {
                    if KitchenKettle.waterState(in: state) == .boiled {
                        if KitchenKettle.lidState(in: state) == .closed {
                            return [
                                ItemAction(
                                    trigger: .primary,
                                    title: "Налить в кружку",
                                    resultText: "Сначала открой крышку чайника.",
                                    sound: nil,
                                    requiresHeldItemID: nil,
                                    producesHeldItem: nil
                                ) { _ in }
                            ]
                        }

                        if fillState(in: state) == .filledHotWater {
                            return [
                                ItemAction(
                                    trigger: .primary,
                                    title: "Налить в кружку",
                                    resultText: "В кружке уже есть горячая вода.",
                                    sound: nil,
                                    requiresHeldItemID: nil,
                                    producesHeldItem: nil
                                ) { _ in }
                            ]
                        }

                        return [
                            ItemAction(
                                trigger: .primary,
                                title: "Налить кипяток в кружку",
                                resultText: "Ты налил кипяток из чайника в кружку.",
                                sound: .itemPlaceMetal01,
                                requiresHeldItemID: KitchenKettle.itemID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                setFillState(.filledHotWater, in: &runtimeState)
                                KitchenKettle.setWaterState(.empty, in: &runtimeState)
                            }
                        ]
                    }

                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Налить в кружку",
                            resultText: "Сначала вскипяти воду в чайнике.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                if state.player.heldItem != nil {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Взять кружку",
                            resultText: "Сначала освободи руки.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                let takeText = state.position(for: itemID) == nil
                    ? "Ты взял кружку."
                    : "Ты поднял кружку."

                return [
                    ItemAction(
                        trigger: .primary,
                        title: "Взять кружку",
                        resultText: takeText,
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: HeldItem(itemID: itemID, name: "кружка")
                    ) { runtimeState in
                        runtimeState.clearItemLocation(itemID: itemID)
                    }
                ]
            }
        )
    }

    static func heldActions(for state: WorldRuntimeState) -> [ItemAction] {
        guard state.player.heldItem?.itemID == itemID else { return [] }

        let description = fillState(in: state) == .filledHotWater
            ? "У тебя в руках кружка с горячей водой."
            : "У тебя в руках пустая кружка."

        return [
            ItemAction(
                trigger: .describe,
                title: "Осмотреть кружку",
                resultText: description,
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { _ in },
            ItemAction(
                trigger: .throwItem,
                title: "Бросить кружку под ноги",
                resultText: "Ты поставил кружку на пол рядом с собой.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setItemLocation(
                    itemID: itemID,
                    roomID: runtimeState.player.roomID,
                    position: nearbyPlacementPosition(for: runtimeState)
                )
            },
            ItemAction(
                trigger: .placeHeldItem,
                title: "Положить кружку рядом",
                resultText: "Ты положил кружку рядом с собой.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setItemLocation(
                    itemID: itemID,
                    roomID: runtimeState.player.roomID,
                    position: nearbyPlacementPosition(for: runtimeState)
                )
            }
        ]
    }

    private static func nearbyPlacementPosition(for state: WorldRuntimeState) -> GridPosition {
        let current = state.player.roomPosition

        switch state.player.roomID {
        case .kitchen:
            if current == GridPosition(x: 3, y: 1) {
                return GridPosition(x: 4, y: 1)
            }
            if current == GridPosition(x: 5, y: 2) {
                return GridPosition(x: 4, y: 2)
            }
            if current == GridPosition(x: 4, y: 2) {
                return GridPosition(x: 4, y: 1)
            }
        case .bathroom:
            if current == GridPosition(x: 2, y: 1) {
                return GridPosition(x: 1, y: 1)
            }
        default:
            break
        }

        return current
    }
}
