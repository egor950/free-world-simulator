import Foundation

enum KitchenStove {
    static let itemID = "kitchen.stove"
    static let kettleBaseHeatDuration: TimeInterval = 16
    static let minimumLoopDuration: TimeInterval = 2.4

    enum Stage: String {
        case off
        case on
        case finishing
    }

    static func stage(in state: WorldRuntimeState) -> Stage {
        state.itemStage(itemID: itemID, as: Stage.self, default: .off)
    }

    static func setStage(_ value: Stage, in state: inout WorldRuntimeState) {
        state.setItemStage(itemID: itemID, stage: value)
    }

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "подставка чайника",
            shortPromptProvider: { state in
                switch stage(in: state) {
                case .off:
                    return "Подставка чайника."
                case .on:
                    return "Включенная подставка чайника."
                case .finishing:
                    return "Подставка чайника. Чайник уже почти докипел."
                }
            },
            fullDescriptionProvider: { state in
                let kettleText: String
                if KitchenKettle.placement(in: state) == .onBase {
                    kettleText = "На подставке стоит электрический чайник."
                } else {
                    kettleText = "Сейчас чайника на подставке нет."
                }

                let stageText: String
                switch stage(in: state) {
                case .off:
                    stageText = "Подставка выключена."
                case .on:
                    stageText = "Подставка включена, чайник греется."
                case .finishing:
                    stageText = "Чайник уже шумит почти как кипящий."
                }
                return "Перед тобой подставка электрического чайника. \(stageText) \(kettleText)"
            },
            actionsProvider: { state in
                let kettleOnBase = KitchenKettle.placement(in: state) == .onBase

                if kettleOnBase {
                    var actions: [ItemAction] = []
                    let waterState = KitchenKettle.waterState(in: state)
                    let baseStage = stage(in: state)

                    switch baseStage {
                    case .off:
                        let resultText: String
                        let shouldTurnOn: Bool

                        if KitchenKettle.lidState(in: state) == .open {
                            resultText = "Сначала закрой крышку чайника."
                            shouldTurnOn = false
                        } else {
                            switch waterState {
                            case .empty:
                                resultText = "Сначала налей воду в чайник."
                                shouldTurnOn = false
                            case .filled:
                                resultText = "Ты включил чайник. Он начинает греться на подставке."
                                shouldTurnOn = true
                            case .boiling:
                                resultText = "Чайник уже греется."
                                shouldTurnOn = false
                            case .boiled:
                                resultText = "Вода уже закипела. Можно снять чайник с подставки."
                                shouldTurnOn = false
                            }
                        }

                        actions.append(
                            ItemAction(
                                trigger: .primary,
                                title: "Включить чайник",
                                resultText: resultText,
                                sound: nil,
                                requiresHeldItemID: nil,
                                producesHeldItem: nil
                            ) { runtimeState in
                                if shouldTurnOn {
                                    setStage(.on, in: &runtimeState)
                                }
                            }
                        )
                    case .on:
                        actions.append(
                            ItemAction(
                                trigger: .primary,
                                title: "Выключить чайник",
                                resultText: "Ты выключил чайник.",
                                sound: nil,
                                requiresHeldItemID: nil,
                                producesHeldItem: nil
                            ) { runtimeState in
                                setStage(.off, in: &runtimeState)
                            }
                        )
                    case .finishing:
                        actions.append(
                            ItemAction(
                                trigger: .primary,
                                title: "Послушать чайник",
                                resultText: "Чайник уже почти докипел. Подожди ещё немного или сними его с подставки.",
                                sound: nil,
                                requiresHeldItemID: nil,
                                producesHeldItem: nil
                            ) { _ in }
                        )
                    }

                    if state.player.heldItem == nil {
                        actions.append(
                            ItemAction(
                                trigger: .placeHeldItem,
                                title: "Снять чайник с подставки",
                                resultText: "Ты снял чайник с подставки.",
                                sound: nil,
                                requiresHeldItemID: nil,
                                producesHeldItem: HeldItem(itemID: KitchenKettle.itemID, name: "электрический чайник")
                            ) { runtimeState in
                                KitchenKettle.setPlacement(.held, in: &runtimeState)
                                setStage(.off, in: &runtimeState)
                            }
                        )
                    }

                    return actions
                }

                if state.player.heldItem?.itemID == KitchenKettle.itemID {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Посмотреть на подставку",
                            resultText: "Чтобы поставить чайник на подставку, удерживай E.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in },
                        ItemAction(
                            trigger: .placeHeldItem,
                            title: "Поставить чайник на подставку",
                            resultText: "Ты поставил чайник на подставку.",
                            sound: .kettleBasePlace,
                            requiresHeldItemID: KitchenKettle.itemID,
                            producesHeldItem: nil
                        ) { runtimeState in
                            runtimeState.player.heldItem = nil
                            runtimeState.clearItemLocation(itemID: KitchenKettle.itemID)
                            KitchenKettle.setPlacement(.onBase, in: &runtimeState)
                            setStage(.off, in: &runtimeState)
                        }
                    ]
                }

                return [
                    ItemAction(
                        trigger: .primary,
                        title: "Проверить подставку",
                        resultText: "Сначала поставь чайник на подставку.",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil
                    ) { _ in }
                ]
            }
        )
    }
}

extension GameViewModel {
    func cancelKettleBoilingTask(resetWaterState: Bool = true) {
        kettleBoilingTask?.cancel()
        kettleBoilingTask = nil
        audioCoordinator.stopKettleHeatingAudio()

        if resetWaterState {
            let waterState = KitchenKettle.waterState(in: state)
            if waterState == .boiling {
                KitchenKettle.setWaterState(.filled, in: &state)
            }
        }
    }

    func syncKettleBoilingTask() {
        let kettleOnBase = KitchenKettle.placement(in: state) == .onBase
        let baseStage = KitchenStove.stage(in: state)
        let waterState = KitchenKettle.waterState(in: state)

        if baseStage == .finishing {
            if kettleOnBase && waterState == .boiling && kettleBoilingTask != nil {
                return
            }

            cancelKettleBoilingTask()
            return
        }

        let lidClosed = KitchenKettle.lidState(in: state) == .closed
        let shouldRunTask = kettleOnBase && baseStage == .on && lidClosed && (waterState == .filled || waterState == .boiling)

        if !shouldRunTask {
            cancelKettleBoilingTask()
            return
        }

        if waterState == .filled {
            KitchenKettle.setWaterState(.boiling, in: &state)
        }

        guard kettleBoilingTask == nil else { return }
        audioCoordinator.startKettleHeatingAudio()

        kettleBoilingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.kettleBoilingTask = nil }

            let startDuration = self.audioCoordinator.duration(of: .kettleHeatStart)
            let finishDuration = self.audioCoordinator.duration(of: .kettleHeatFinish)
            let leadDuration = max(
                KitchenStove.kettleBaseHeatDuration - finishDuration,
                startDuration + KitchenStove.minimumLoopDuration
            )

            try? await Task.sleep(nanoseconds: UInt64(leadDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let stillHeating =
                KitchenKettle.placement(in: self.state) == .onBase &&
                KitchenStove.stage(in: self.state) == .on &&
                KitchenKettle.lidState(in: self.state) == .closed &&
                KitchenKettle.waterState(in: self.state) == .boiling

            guard stillHeating else { return }

            KitchenStove.setStage(.finishing, in: &self.state)
            self.refreshScreenState()
            self.audioCoordinator.finishKettleHeatingAudio()

            try? await Task.sleep(nanoseconds: UInt64(finishDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let stillFinishing =
                KitchenKettle.placement(in: self.state) == .onBase &&
                KitchenStove.stage(in: self.state) == .finishing &&
                KitchenKettle.lidState(in: self.state) == .closed &&
                KitchenKettle.waterState(in: self.state) == .boiling

            guard stillFinishing else { return }

            KitchenKettle.setWaterState(.boiled, in: &self.state)
            KitchenStove.setStage(.off, in: &self.state)
            self.refreshScreenState()
            self.addLog("Вода в чайнике закипела.")
            self.announce("Вода в чайнике закипела.")
        }
    }
}
