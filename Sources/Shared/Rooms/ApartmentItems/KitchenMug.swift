import Foundation

enum KitchenMug {
    static let itemID = "kitchen.mug"
    static let extraStoreMugPrefix = "groceryStore.mug."
    private static let generatedCounterKey = "groceryStore.mug.counter"

    enum FillState: String {
        case empty
        case filledHotWater
        case hotTea
        case sweetTea
    }

    private static let kitchenMugTakenKey = "kitchen.mug.taken"

    static func isKitchenMugTaken(in state: WorldRuntimeState) -> Bool {
        state.itemStage(itemID: kitchenMugTakenKey, as: BoolBackedStage.self, default: BoolBackedStage(value: false)).value
    }

    static func markKitchenMugTaken(in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: kitchenMugTakenKey, stage: BoolBackedStage(value: true))
    }

    static func isMugItemID(_ candidateID: String) -> Bool {
        candidateID == itemID || candidateID.hasPrefix(extraStoreMugPrefix)
    }

    static func fillState(in state: WorldRuntimeState, itemID: String = itemID) -> FillState {
        state.itemStage(itemID: itemID, as: FillState.self, default: .empty)
    }

    static func setFillState(_ value: FillState, in state: inout WorldRuntimeState, itemID: String = itemID) {
        state.setItemStage(itemID: itemID, stage: value)
    }

    static func make(itemID definitionItemID: String = itemID, name: String = "кружка") -> ItemDefinition {
        ItemDefinition(
            id: definitionItemID,
            name: name,
            shortPromptProvider: { state in
                let fill = fillState(in: state, itemID: definitionItemID)
                let isHeld = state.player.heldItem?.itemID == definitionItemID
                switch fill {
                case .filledHotWater:
                    return isHeld ? "В руках кружка с горячей водой." : "Кружка с горячей водой."
                case .hotTea:
                    return isHeld ? "В руках кружка с чаем." : "Кружка с чаем."
                case .sweetTea:
                    return isHeld ? "В руках кружка со сладким чаем." : "Кружка со сладким чаем."
                case .empty:
                    return isHeld ? "В руках пустая кружка." : "Пустая кружка."
                }
            },
            fullDescriptionProvider: { state in
                let fill = fillState(in: state, itemID: definitionItemID)
                let contentText: String
                switch fill {
                case .filledHotWater:
                    contentText = "Внутри горячая вода."
                case .hotTea:
                    contentText = "Внутри заваренный чай."
                case .sweetTea:
                    contentText = "Внутри сладкий чай."
                case .empty:
                    contentText = "Пока она пустая."
                }

                if state.player.heldItem?.itemID == definitionItemID {
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

                        if fillState(in: state, itemID: definitionItemID) == .filledHotWater {
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
                                setFillState(.filledHotWater, in: &runtimeState, itemID: definitionItemID)
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

                let takeText = state.position(for: definitionItemID) == nil
                    ? "Ты взял кружку."
                    : "Ты поднял кружку."

                return [
                    ItemAction(
                        trigger: .primary,
                        title: "Взять кружку",
                        resultText: takeText,
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: HeldItem(itemID: definitionItemID, name: name)
                    ) { runtimeState in
                        runtimeState.clearItemLocation(itemID: definitionItemID)
                        if definitionItemID == KitchenMug.itemID {
                            KitchenMug.markKitchenMugTaken(in: &runtimeState)
                        }
                    }
                ]
            }
        )
    }

    static func heldActions(for state: WorldRuntimeState, itemID heldItemID: String) -> [ItemAction] {
        guard state.player.heldItem?.itemID == heldItemID else { return [] }

        let description: String
        switch fillState(in: state, itemID: heldItemID) {
        case .filledHotWater:
            description = "У тебя в руках кружка с горячей водой."
        case .hotTea:
            description = "У тебя в руках кружка с чаем."
        case .sweetTea:
            description = "У тебя в руках кружка со сладким чаем."
        case .empty:
            description = "У тебя в руках пустая кружка."
        }

        var actions: [ItemAction] = [
            ItemAction(
                trigger: .describe,
                title: "Осмотреть кружку",
                resultText: description,
                sound: nil,
                requiresHeldItemID: heldItemID,
                producesHeldItem: nil
            ) { _ in },
            ItemAction(
                trigger: .throwItem,
                title: "Бросить кружку под ноги",
                resultText: "Ты поставил кружку на пол рядом с собой.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: heldItemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setItemLocation(
                    itemID: heldItemID,
                    roomID: runtimeState.player.roomID,
                    position: nearbyPlacementPosition(for: runtimeState)
                )
            },
            ItemAction(
                trigger: .placeHeldItem,
                title: "Положить кружку рядом",
                resultText: "Ты положил кружку рядом с собой.",
                sound: .itemPlaceMetal01,
                requiresHeldItemID: heldItemID,
                producesHeldItem: nil
            ) { runtimeState in
                runtimeState.player.heldItem = nil
                runtimeState.setItemLocation(
                    itemID: heldItemID,
                    roomID: runtimeState.player.roomID,
                    position: nearbyPlacementPosition(for: runtimeState)
                )
            }
        ]

        if state.player.roomID == .hallway,
           state.player.roomPosition == GridPosition(x: 4, y: 1) {
            let fill = fillState(in: state, itemID: heldItemID)
            let price: Int
            let title: String
            let resultText: String
            switch fill {
            case .sweetTea:
                price = TeaShop.sweetTeaPrice
                title = "Продать сладкий чай"
                resultText = "Кто-то купил кружку сладкого чая за \(price) монет!"
            case .hotTea:
                price = TeaShop.teaPrice
                title = "Продать чай"
                resultText = "Кто-то купил кружку чая за \(price) монет!"
            case .filledHotWater:
                price = TeaShop.mugPrice
                title = "Продать кружку кипятка"
                resultText = "Кто-то купил кружку кипятка за \(price) монет!"
            case .empty:
                price = 0
                title = ""
                resultText = ""
            }

            if price > 0 {
                actions.append(
                    ItemAction(
                        trigger: .primary,
                        title: title,
                        resultText: resultText,
                        sound: .itemPlaceMetal01,
                        requiresHeldItemID: heldItemID,
                        producesHeldItem: nil
                    ) { runtimeState in
                        runtimeState.player.heldItem = nil
                        TeaShop.addCoins(price, in: &runtimeState)
                    }
                )
            }
        }

        return actions
    }

    static func makeGeneratedHeldItem(in state: inout WorldRuntimeState) -> HeldItem {
        let nextIndex = (Int(state.itemStage(itemID: generatedCounterKey, as: IntBackedStage.self, default: IntBackedStage(value: 1)).rawValue) ?? 1)
        let newID = extraStoreMugPrefix + String(nextIndex)
        state.setRawItemStage(itemID: generatedCounterKey, rawValue: String(nextIndex + 1))
        setFillState(.empty, in: &state, itemID: newID)
        state.clearItemLocation(itemID: newID)
        return HeldItem(itemID: newID, name: "кружка")
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
        case .teaRoom:
            if current == GridPosition(x: 2, y: 1) {
                return GridPosition(x: 1, y: 1)
            }
            if current == GridPosition(x: 3, y: 1) {
                return GridPosition(x: 2, y: 1)
            }
        default:
            break
        }

        return current
    }
}

private struct IntBackedStage: RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(value: Int) {
        self.rawValue = String(value)
    }
}

private struct BoolBackedStage: RawRepresentable {
    let rawValue: String
    var value: Bool { rawValue == "true" }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(value: Bool) {
        self.rawValue = value ? "true" : "false"
    }
}
