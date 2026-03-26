import Foundation
import GameplayKit

final class GroceryStoreClerkMachine {
    private final class IdleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ListingGoodsState.self ||
            stateClass == GivingItemState.self ||
            stateClass == RefusingState.self
        }
    }

    private final class ListingGoodsState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CooldownState.self
        }
    }

    private final class GivingItemState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CooldownState.self
        }
    }

    private final class RefusingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CooldownState.self
        }
    }

    private final class CooldownState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    private let machine = GKStateMachine(states: [
        IdleState(),
        ListingGoodsState(),
        GivingItemState(),
        RefusingState(),
        CooldownState()
    ])

    init() {
        reset()
    }

    func reset() {
        _ = machine.enter(IdleState.self)
    }

    func listGoods() -> String {
        _ = machine.enter(ListingGoodsState.self)
        defer { enterCooldown() }
        return "Продавец говорит: здесь есть вода, хлеб, печенье и простая магазинная мелочь. Пустые кружки стоят на полке, можешь взять хоть несколько."
    }

    func giveMugIfPossible(handsBusy: Bool) -> String {
        if handsBusy {
            _ = machine.enter(RefusingState.self)
            defer { enterCooldown() }
            return "Продавец говорит: сначала освободи руки, потом дам кружку."
        }

        _ = machine.enter(GivingItemState.self)
        defer { enterCooldown() }
        return "Продавец протянул тебе пустую кружку."
    }

    func askFreebie() -> String {
        _ = machine.enter(RefusingState.self)
        defer { enterCooldown() }
        return "Продавец усмехнулся: бесплатно можешь взять пустую кружку. Остальное потом, когда в игре появятся деньги."
    }

    func askWater() -> String {
        _ = machine.enter(ListingGoodsState.self)
        defer { enterCooldown() }
        return "Продавец говорит: воду пока просто держим на полке как часть магазина. Зато пустую кружку можешь взять хоть сейчас и нести домой."
    }

    private func enterCooldown() {
        _ = machine.enter(CooldownState.self)
        _ = machine.enter(IdleState.self)
    }
}

extension GameViewModel {
    func handleSpecialInteraction(for action: ItemAction) -> String? {
        guard let interactionID = action.interactionID else {
            return nil
        }

        switch interactionID {
        case GroceryStoreRoom.listGoodsInteractionID:
            return groceryStoreClerkMachine.listGoods()
        case GroceryStoreRoom.askForMugInteractionID:
            guard state.player.heldItem == nil else {
                return groceryStoreClerkMachine.giveMugIfPossible(handsBusy: true)
            }
            state.player.heldItem = KitchenMug.makeGeneratedHeldItem(in: &state)
            return groceryStoreClerkMachine.giveMugIfPossible(handsBusy: false)
        case GroceryStoreRoom.askFreebieInteractionID:
            return groceryStoreClerkMachine.askFreebie()
        case GroceryStoreRoom.askWaterInteractionID:
            return groceryStoreClerkMachine.askWater()
        case GroceryStoreRoom.takeShelfMugInteractionID:
            guard state.player.heldItem == nil else {
                return "Сначала освободи руки, потом бери еще одну кружку."
            }
            state.player.heldItem = KitchenMug.makeGeneratedHeldItem(in: &state)
            return "Ты взял с полки пустую кружку."
        default:
            return nil
        }
    }

    func groceryStoreEmptyDescription() -> String {
        let pos = state.player.roomPosition

        if pos == GroceryStoreRoom.entryPosition {
            return "Ты стоишь у двери продуктового. Слева улица, а впереди уже торговый зал."
        }

        if pos.x <= 2 {
            return "Ты рядом со входом в магазин. Позади дверь, а дальше впереди прилавок и полки."
        }

        if pos.x >= GroceryStoreRoom.width - 4 && pos.y <= 3 {
            return "Ты у правой верхней части магазина, рядом полка с кружками."
        }

        if pos.x >= GroceryStoreRoom.width - 4 && pos.y >= 4 {
            return "Ты у правой части магазина, рядом полка с товарами."
        }

        return "Ты стоишь в проходе продуктового. Здесь можно подойти к прилавку, к полке с кружками или вернуться к выходу."
    }
}
