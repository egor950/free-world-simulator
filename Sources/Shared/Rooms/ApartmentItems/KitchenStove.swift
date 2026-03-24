import Foundation

enum KitchenStove {
    static let itemID = "kitchen.stove"
    static let kettleBoilDuration: TimeInterval = 4.2

    enum Stage: String {
        case off
        case on
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
            name: "плита",
            shortPromptProvider: { state in
                stage(in: state) == .on ? "Включенная плита." : "Плита."
            },
            fullDescriptionProvider: { state in
                let kettleText: String
                if KitchenKettle.placement(in: state) == .onStove {
                    kettleText = "На плите стоит чайник."
                } else {
                    kettleText = "Сейчас чайника на плите нет."
                }

                let stageText = stage(in: state) == .on ? "Плита включена." : "Плита выключена."
                return "Перед тобой плита. \(stageText) \(kettleText)"
            },
            actionsProvider: { state in
                let kettleOnStove = KitchenKettle.placement(in: state) == .onStove

                if kettleOnStove {
                    var actions: [ItemAction] = []
                    let waterState = KitchenKettle.waterState(in: state)
                    let stoveStage = stage(in: state)

                    if stoveStage == .off {
                        let resultText: String
                        let shouldTurnOn: Bool

                        switch waterState {
                        case .empty:
                            resultText = "Сначала налей воду в чайник."
                            shouldTurnOn = false
                        case .filled:
                            resultText = "Ты включил плиту. Чайник начинает греться."
                            shouldTurnOn = true
                        case .boiling:
                            resultText = "Чайник уже греется."
                            shouldTurnOn = false
                        case .boiled:
                            resultText = "Вода уже закипела. Можно выключить плиту и снять чайник."
                            shouldTurnOn = false
                        }

                        actions.append(
                            ItemAction(
                                trigger: .primary,
                                title: "Включить плиту",
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
                    } else {
                        actions.append(
                            ItemAction(
                                trigger: .primary,
                                title: "Выключить плиту",
                                resultText: "Ты выключил плиту.",
                                sound: nil,
                                requiresHeldItemID: nil,
                                producesHeldItem: nil
                            ) { runtimeState in
                                setStage(.off, in: &runtimeState)
                            }
                        )
                    }

                    if stoveStage == .off && state.player.heldItem == nil {
                        actions.append(
                            ItemAction(
                                trigger: .placeHeldItem,
                                title: "Снять чайник с плиты",
                                resultText: "Ты снял чайник с плиты.",
                                sound: .itemPlaceMetal01,
                                requiresHeldItemID: nil,
                                producesHeldItem: HeldItem(itemID: KitchenKettle.itemID, name: "чайник")
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
                            title: "Посмотреть на плиту",
                            resultText: "Чтобы поставить чайник на плиту, удерживай E.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in },
                        ItemAction(
                            trigger: .placeHeldItem,
                            title: "Поставить чайник на плиту",
                            resultText: "Ты поставил чайник на плиту.",
                            sound: .itemPlaceMetal01,
                            requiresHeldItemID: KitchenKettle.itemID,
                            producesHeldItem: nil
                        ) { runtimeState in
                            runtimeState.player.heldItem = nil
                            runtimeState.clearItemLocation(itemID: KitchenKettle.itemID)
                            KitchenKettle.setPlacement(.onStove, in: &runtimeState)
                            setStage(.off, in: &runtimeState)
                        }
                    ]
                }

                return [
                    ItemAction(
                        trigger: .primary,
                        title: "Проверить плиту",
                        resultText: "Сначала поставь чайник на плиту.",
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

        if resetWaterState, KitchenKettle.waterState(in: state) == .boiling {
            KitchenKettle.setWaterState(.filled, in: &state)
        }
    }

    func syncKettleBoilingTask() {
        let kettleOnStove = KitchenKettle.placement(in: state) == .onStove
        let stoveOn = KitchenStove.stage(in: state) == .on
        let waterState = KitchenKettle.waterState(in: state)

        let shouldRunTask = kettleOnStove && stoveOn && (waterState == .filled || waterState == .boiling)

        if !shouldRunTask {
            cancelKettleBoilingTask()
            return
        }

        if waterState == .filled {
            KitchenKettle.setWaterState(.boiling, in: &state)
        }

        guard kettleBoilingTask == nil else { return }

        kettleBoilingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(KitchenStove.kettleBoilDuration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }

            self.kettleBoilingTask = nil

            let stillHeating =
                KitchenKettle.placement(in: self.state) == .onStove &&
                KitchenStove.stage(in: self.state) == .on &&
                KitchenKettle.waterState(in: self.state) == .boiling

            guard stillHeating else { return }

            KitchenKettle.setWaterState(.boiled, in: &self.state)
            self.refreshScreenState()
            self.addLog("Вода в чайнике закипела.")
            self.announce("Вода в чайнике закипела.")
        }
    }
}
