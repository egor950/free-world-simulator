import Foundation

enum HallwayCoatRack {
    static let itemID = "hallway.coatRack"

    static func make() -> ItemDefinition {
        ItemDefinition(
            id: itemID,
            name: "вешалка",
            shortPromptProvider: { _ in "Вешалка." },
            fullDescriptionProvider: { _ in
                "Перед тобой вешалка с легкой курткой. Можно снять куртку, пнуть стойку или резко ее толкнуть."
            },
            actionsProvider: { _ in
                [
                    ItemAction(trigger: .primary, title: "Снять куртку", resultText: "Ты снял куртку и быстро ощупал карманы. Внутри пусто.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in },
                    ItemAction(trigger: .force, title: "Пнуть вешалку", resultText: "Ты пнул вешалку. Она качнулась и жалобно стукнула по полу.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in },
                    ItemAction(trigger: .throwItem, title: "Толкнуть вешалку", resultText: "Ты резко толкнул стойку. Она проехала немного в сторону и снова остановилась.", sound: nil, requiresHeldItemID: nil, producesHeldItem: nil) { _ in }
                ]
            }
        )
    }
}
