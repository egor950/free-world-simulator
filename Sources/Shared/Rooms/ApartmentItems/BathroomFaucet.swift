import Foundation

enum BathroomFaucet {
    static let itemID = "bathroom.faucet"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "кран",
            shortPromptProvider: { _ in "Кран с водой." },
            fullDescriptionProvider: { _ in
                "Перед тобой кран с водой. Здесь можно налить воду в открытый чайник."
            },
            actionsProvider: { state in
                guard state.player.heldItem?.itemID == KitchenKettle.itemID else {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Повернуть кран",
                            resultText: "Пока наливать не во что.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                if KitchenKettle.lidState(in: state) == .closed {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Налить воду в чайник",
                            resultText: "Сначала открой крышку чайника.",
                            sound: nil,
                            requiresHeldItemID: KitchenKettle.itemID,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                switch KitchenKettle.waterState(in: state) {
                case .empty:
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Налить воду в чайник",
                            resultText: "Ты налил воду в чайник.",
                            sound: nil,
                            requiresHeldItemID: KitchenKettle.itemID,
                            producesHeldItem: nil
                        ) { runtimeState in
                            KitchenKettle.setWaterState(.filled, in: &runtimeState)
                        }
                    ]
                case .filled:
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Налить воду в чайник",
                            resultText: "В чайнике уже есть вода.",
                            sound: nil,
                            requiresHeldItemID: KitchenKettle.itemID,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                case .boiling, .boiled:
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Налить воду в чайник",
                            resultText: "Сейчас в чайнике уже не пусто.",
                            sound: nil,
                            requiresHeldItemID: KitchenKettle.itemID,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }
            }
        )
    }
}
