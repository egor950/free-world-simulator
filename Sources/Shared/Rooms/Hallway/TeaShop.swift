import Foundation

enum TeaShop {
    static let itemID = "hallway.teaShop"
    static let mugPrice = 5
    static let teaPrice = 8
    static let sweetTeaPrice = 10

    static func coins(in state: WorldRuntimeState) -> Int {
        state.player.coins
    }

    static func addCoins(_ amount: Int, in state: inout WorldRuntimeState) {
        state.player.coins += amount
    }

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "стойка чайного бизнеса",
            shortPromptProvider: { state in
                let coins = coins(in: state)
                if coins > 0 {
                    return "Стойка чайного бизнеса. Заработано: \(coins) монет."
                }
                return "Стойка чайного бизнеса."
            },
            fullDescriptionProvider: { state in
                let coins = coins(in: state)
                if coins > 0 {
                    return "Перед тобой стойка чайного бизнеса. Заработано: \(coins) монет. Цены: кипяток — \(mugPrice) монет, чай — \(teaPrice) монет, сладкий чай — \(sweetTeaPrice) монет.\n\nКак заработать:\n1. Возьми кружку на кухне (E)\n2. Налей кипяток (E рядом с кружкой у чайника)\n3. Продай на стойке (E) — \(mugPrice) монет\nИли завари чай в чайной — больше прибыль."
                }
                return "Перед тобой стойка чайного бизнеса. Цены: кипяток — \(mugPrice) монет, чай — \(teaPrice) монет, сладкий чай — \(sweetTeaPrice) монет.\n\nКак заработать:\n1. Возьми кружку на кухне (E)\n2. Налей кипяток (E рядом с кружкой у чайника)\n3. Продай на стойке (E) — \(mugPrice) монет\nИли завари чай в чайной — больше прибыль."
            },
            actionsProvider: { state in
                let coins = coins(in: state)

                if state.player.heldItem?.itemID == KitchenKettle.itemID {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Продать чайник",
                            resultText: "Чайник не продаётся. Нужны кружки с кипятком.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                if let heldItemID = state.player.heldItem?.itemID,
                   KitchenMug.isMugItemID(heldItemID) {
                    let fill = KitchenMug.fillState(in: state, itemID: heldItemID)
                    switch fill {
                    case .sweetTea:
                        return [
                            ItemAction(
                                trigger: .primary,
                                title: "Продать сладкий чай",
                                resultText: "Кто-то купил кружку сладкого чая за \(sweetTeaPrice) монет!",
                                sound: .itemPlaceMetal01,
                                requiresHeldItemID: heldItemID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                runtimeState.player.heldItem = nil
                                addCoins(sweetTeaPrice, in: &runtimeState)
                            }
                        ]
                    case .hotTea:
                        return [
                            ItemAction(
                                trigger: .primary,
                                title: "Продать чай",
                                resultText: "Кто-то купил кружку чая за \(teaPrice) монет!",
                                sound: .itemPlaceMetal01,
                                requiresHeldItemID: heldItemID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                runtimeState.player.heldItem = nil
                                addCoins(teaPrice, in: &runtimeState)
                            }
                        ]
                    case .filledHotWater:
                        return [
                            ItemAction(
                                trigger: .primary,
                                title: "Продать кружку кипятка",
                                resultText: "Кто-то купил кружку кипятка за \(mugPrice) монет!",
                                sound: .itemPlaceMetal01,
                                requiresHeldItemID: heldItemID,
                                producesHeldItem: nil
                            ) { runtimeState in
                                runtimeState.player.heldItem = nil
                                addCoins(mugPrice, in: &runtimeState)
                            }
                        ]
                    case .empty:
                        break
                    }
                }

                if coins > 0 {
                    return [
                        ItemAction(
                            trigger: .primary,
                            title: "Посмотреть кассу",
                            resultText: "На стойке \(coins) монет. Продавай кружки с кипятком, чтобы заработать больше.",
                            sound: nil,
                            requiresHeldItemID: nil,
                            producesHeldItem: nil
                        ) { _ in }
                    ]
                }

                return [
                    ItemAction(
                        trigger: .primary,
                        title: "Посмотреть стойку",
                        resultText: "Стойка пуста. Бери кружку в продуктовом, наливай кипяток и продавай здесь.",
                        sound: nil,
                        requiresHeldItemID: nil,
                        producesHeldItem: nil
                    ) { _ in }
                ]
            }
        )
    }
}
