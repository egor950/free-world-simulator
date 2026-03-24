import Foundation

enum KitchenKettle {
    static let itemID = "kitchen.kettle"
    private static let lidStateKey = itemID + ".lid"
    private static let placementKey = itemID + ".placement"

    enum WaterState: String {
        case empty
        case filled
        case boiling
        case boiled
    }

    enum LidState: String {
        case closed
        case open
    }

    enum Placement: String {
        case defaultSpot
        case held
        case onFloor
        case onStove
    }

    static func waterState(in state: WorldRuntimeState) -> WaterState {
        state.itemStage(itemID: itemID, as: WaterState.self, default: .empty)
    }

    static func setWaterState(_ value: WaterState, in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: itemID, stage: value)
    }

    static func lidState(in state: WorldRuntimeState) -> LidState {
        state.itemStage(itemID: lidStateKey, as: LidState.self, default: .closed)
    }

    static func setLidState(_ value: LidState, in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: lidStateKey, stage: value)
    }

    static func placement(in state: WorldRuntimeState) -> Placement {
        if state.player.heldItem?.itemID == itemID {
            return .held
        }

        if state.itemStage(itemID: placementKey, as: Placement.self, default: .defaultSpot) == .onStove {
            return .onStove
        }

        if state.position(for: itemID) != nil || state.room(for: itemID) != nil {
            return .onFloor
        }

        return .defaultSpot
    }

    static func setPlacement(_ value: Placement, in state: inout WorldRuntimeState) {
        switch value {
        case .defaultSpot:
            state.setItemStage(itemID: placementKey, stage: Optional<Placement>.none)
        default:
            state.setItemStage(itemID: placementKey, stage: value)
        }
    }

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "чайник",
            shortPromptProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    return "В руках чайник."
                }

                if placement(in: state) == .onFloor {
                    return "Чайник рядом."
                }

                return "Чайник."
            },
            fullDescriptionProvider: { state in
                let lidText = lidState(in: state) == .open ? "Крышка открыта." : "Крышка закрыта."
                let waterText: String
                switch waterState(in: state) {
                case .empty:
                    waterText = "Внутри пусто."
                case .filled:
                    waterText = "Внутри холодная вода."
                case .boiling:
                    waterText = "Вода греется и вот-вот закипит."
                case .boiled:
                    waterText = "Внутри уже кипяток."
                }

                if state.player.heldItem?.itemID == itemID {
                    return "У тебя в руках чайник. \(lidText) \(waterText) Его можно поставить рядом, открыть или закрыть крышку."
                }

                return "Перед тобой чайник. \(lidText) \(waterText)"
            },
            actionsProvider: { state in
                if state.player.heldItem?.itemID == itemID {
                    return []
                }

                if state.player.heldItem != nil {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Взять чайник",
                            resultText: "Сначала освободи руки.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                let takeText = placement(in: state) == .onFloor
                    ? "Ты поднял чайник."
                    : "Ты взял чайник."

                return [
                    ItemAction(
                        trigger: .primary,
                        title: "Взять чайник",
                        resultText: takeText,
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: HeldItem(itemID: itemID, name: "чайник")
                    ) { runtimeState in
                        runtimeState.clearItemLocation(itemID: itemID)
                        setPlacement(.held, in: &runtimeState)
                    }
                ]
            }
        )
    }

    static func heldActions(for state: WorldRuntimeState) -> [ItemAction] {
        guard state.player.heldItem?.itemID == itemID else { return [] }

        let describeText = makeHeldDescription(for: state)
        let lidIsClosed = lidState(in: state) == .closed

        return [
            ItemAction(
                trigger: .describe,
                title: "Осмотреть чайник",
                resultText: describeText,
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { _ in },
            ItemAction(
                trigger: .primary,
                title: lidIsClosed ? "Открыть крышку" : "Закрыть крышку",
                resultText: lidIsClosed ? "Ты открыл крышку чайника." : "Ты закрыл крышку чайника.",
                sound: nil,
                requiresHeldItemID: itemID,
                producesHeldItem: nil
            ) { runtimeState in
                setLidState(lidIsClosed ? .open : .closed, in: &runtimeState)
            },
            ItemAction(
                trigger: .throwItem,
                title: "Бросить чайник под ноги",
                resultText: "Ты поставил чайник на пол рядом с собой.",
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
                setPlacement(.onFloor, in: &runtimeState)
            },
            ItemAction(
                trigger: .placeHeldItem,
                title: "Положить чайник рядом",
                resultText: "Ты положил чайник рядом с собой.",
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
                setPlacement(.onFloor, in: &runtimeState)
            }
        ]
    }

    private static func makeHeldDescription(for state: WorldRuntimeState) -> String {
        let lidText = lidState(in: state) == .open ? "Крышка открыта." : "Крышка закрыта."
        let waterText: String
        switch waterState(in: state) {
        case .empty:
            waterText = "Чайник пустой."
        case .filled:
            waterText = "В чайнике холодная вода."
        case .boiling:
            waterText = "Вода внутри греется."
        case .boiled:
            waterText = "Внутри уже кипяток."
        }
        return "У тебя в руках чайник. \(lidText) \(waterText)"
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
            if current == GridPosition(x: 2, y: 1) {
                return GridPosition(x: 2, y: 2)
            }
        case .bathroom:
            if current == GridPosition(x: 2, y: 1) {
                return GridPosition(x: 1, y: 1)
            }
            if current == GridPosition(x: 3, y: 1) {
                return GridPosition(x: 2, y: 2)
            }
        default:
            break
        }

        return current
    }
}
