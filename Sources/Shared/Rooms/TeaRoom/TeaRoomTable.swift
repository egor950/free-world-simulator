import Foundation

enum TeaRoomTable {
    static let itemID = "teaRoom.table"
    static let brewingDuration: TimeInterval = 8

    enum Stage: String {
        case empty
        case mugPlaced
        case brewing
        case brewed
        case sugarAdded
    }

    static func stage(in state: WorldRuntimeState) -> Stage {
        state.itemStage(itemID: itemID, as: Stage.self, default: .empty)
    }

    static func setStage(_ value: Stage, in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: itemID, stage: value)
    }

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "столик для чая",
            shortPromptProvider: { state in
                switch stage(in: state) {
                case .empty:
                    return "Столик для заваривания чая."
                case .mugPlaced:
                    return "На столике стоит кружка с кипятком."
                case .brewing:
                    return "На столике кружка. Пакетик чая заваривается..."
                case .brewed:
                    return "На столике кружка с готовым чаем."
                case .sugarAdded:
                    return "На столике кружка со сладким чаем."
                }
            },
            fullDescriptionProvider: { state in
                switch stage(in: state) {
                case .empty:
                    return "Перед тобой небольшой деревянный столик. На нём можно заварить чай: поставить кружку с кипятком и добавить пакетик."
                case .mugPlaced:
                    return "На столике стоит кружка с горячей водой. Добавь пакетик чая, чтобы начать заваривание."
                case .brewing:
                    return "Пакетик чая медленно отдаёт свой вкус горячей воде. Ещё чуть-чуть..."
                case .brewed:
                    return "Чай готов! Можно добавить сахар или взять кружку и продать на стойке."
                case .sugarAdded:
                    return "Сахар растворился в чае. Кружка со сладким чаем готова к продаже."
                }
            },
            actionsProvider: { state in
                let currentStage = stage(in: state)
                let heldItemID = state.player.heldItem?.itemID

                switch currentStage {
                case .empty:
                    if let heldID = heldItemID,
                       KitchenMug.isMugItemID(heldID),
                       KitchenMug.fillState(in: state, itemID: heldID) == .filledHotWater {
                        return [
                            ItemAction(
                                trigger: .primary,
                                title: "Поставить кружку на столик",
                                resultText: "Ты поставил кружку с кипятком на столик.",
                                sound: .itemPlaceMetal01,
                                requiresHeldItemID: heldID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                runtimeState.player.heldItem = nil
                                KitchenMug.setFillState(.filledHotWater, in: &runtimeState, itemID: heldID)
                                setMugIDOnTable(heldID, in: &runtimeState)
                                setStage(.mugPlaced, in: &runtimeState)
                            }
                        ]
                    }

                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Осмотреть столик",
                            resultText: "Столик для заваривания чая. Поставь сюда кружку с кипятком и добавь пакетик чая.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]

                case .mugPlaced:
                    if let heldID = heldItemID,
                       heldID == GroceryStoreTeabag.itemID {
                        return [
                            ItemAction(
                                trigger: .primary,
                                title: "Добавить пакетик чая",
                                resultText: "Ты опустил пакетик чая в кружку. Чай заварился!",
                                sound: nil,
                                requiresHeldItemID: heldID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                runtimeState.player.heldItem = nil
                                let mugID = mugItemIDOnTable(in: runtimeState)
                                KitchenMug.setFillState(.hotTea, in: &runtimeState, itemID: mugID)
                                setStage(.brewed, in: &runtimeState)
                            }
                        ]
                    }

                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Осмотреть столик",
                            resultText: "На столике кружка с кипятком. Нужен пакетик чая, чтобы заварить.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in },
                        ItemAction(
                            trigger: .force,
                            title: "Взять кружку со столика",
                            resultText: "Ты взял кружку со столика.",
                            sound: .itemPlaceMetal01,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { runtimeState in
                            findAndTakeMug(from: &runtimeState)
                        }
                    ]

                case .brewed, .sugarAdded:
                    var actions: [ItemAction] = []

                    if currentStage == .brewed,
                       let heldID = heldItemID,
                       heldID == GroceryStoreSugar.itemID {
                        actions.append(
                            ItemAction(
                                trigger: .primary,
                                title: "Добавить сахар",
                                resultText: "Ты насыпал сахар в чай. Получился сладкий чай!",
                                sound: nil,
                                requiresHeldItemID: heldID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                runtimeState.player.heldItem = nil
                                let mugID = mugItemIDOnTable(in: runtimeState)
                                KitchenMug.setFillState(.sweetTea, in: &runtimeState, itemID: mugID)
                                setStage(.sugarAdded, in: &runtimeState)
                            }
                        )
                    }

                    actions.append(
                        ItemAction(
                            trigger: .force,
                            title: "Взять кружку со столика",
                            resultText: "Ты взял кружку со столика.",
                            sound: .itemPlaceMetal01,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { runtimeState in
                            findAndTakeMug(from: &runtimeState)
                        }
                    )

                    return actions

                case .brewing:
                    return [
                        ItemAction(
                            trigger: .force,
                            title: "Взять кружку со столика",
                            resultText: "Ты забрал кружку раньше времени. Чай не заварился до конца.",
                            sound: .itemPlaceMetal01,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { runtimeState in
                            let mugID = mugItemIDOnTable(in: runtimeState)
                            KitchenMug.setFillState(.filledHotWater, in: &runtimeState, itemID: mugID)
                            findAndTakeMug(from: &runtimeState)
                        }
                    ]
                }
            }
        )
    }

    static func mugItemIDOnTable(in state: WorldRuntimeState) -> String {
        state.itemStage(itemID: itemID + ".mugID", as: MugIDStage.self, default: MugIDStage(rawValue: KitchenMug.itemID)).rawValue
    }

    static func setMugIDOnTable(_ mugID: String, in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: itemID + ".mugID", stage: MugIDStage(rawValue: mugID))
    }

    static func clearMugIDOnTable(in state: inout WorldRuntimeState) {
        state.setRawItemStage(itemID: itemID + ".mugID", rawValue: nil)
    }

    static func findAndTakeMug(from state: inout WorldRuntimeState) {
        let mugID = mugItemIDOnTable(in: state)
        state.player.heldItem = HeldItem(itemID: mugID, name: "кружка")
        clearMugIDOnTable(in: &state)
        setStage(.empty, in: &state)
    }
}

private struct MugIDStage: RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}
