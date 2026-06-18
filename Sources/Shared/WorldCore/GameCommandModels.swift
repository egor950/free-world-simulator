import Foundation

enum GameCommand: String, Identifiable {
    case moveForward
    case moveBackward
    case moveLeft
    case moveRight
    case primaryAction
    case forceAction
    case throwObject
    case describeFocus
    case placeHeldItem
    case inventoryToggle
    case inventoryQuickAction
    case locationMenuToggle
    case locationMenuConfirm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveForward:
            return "Вперед"
        case .moveBackward:
            return "Назад"
        case .moveLeft:
            return "Влево"
        case .moveRight:
            return "Вправо"
        case .primaryAction:
            return "Действие"
        case .forceAction:
            return "Ударить"
        case .throwObject:
            return "Сбросить"
        case .describeFocus:
            return "Описание"
        case .placeHeldItem:
            return "Положить"
        case .inventoryToggle:
            return "Инвентарь"
        case .inventoryQuickAction:
            return "Инвентарь действие"
        case .locationMenuToggle:
            return "Маяк"
        case .locationMenuConfirm:
            return "Подтвердить маяк"
        }
    }

    var macKeyTitle: String {
        switch self {
        case .moveForward:
            return "Стрелка вверх"
        case .moveBackward:
            return "Стрелка вниз"
        case .moveLeft:
            return "Стрелка влево"
        case .moveRight:
            return "Стрелка вправо"
        case .primaryAction:
            return "E"
        case .forceAction:
            return "F"
        case .throwObject:
            return "Пробел"
        case .describeFocus:
            return "Q"
        case .placeHeldItem:
            return "Удержание E"
        case .inventoryToggle:
            return "I / Escape"
        case .inventoryQuickAction:
            return "C"
        case .locationMenuToggle:
            return "X"
        case .locationMenuConfirm:
            return "Enter"
        }
    }

    static func parse(_ rawValue: String) -> GameCommand? {
        switch rawValue.lowercased() {
        case "forward", "move_forward", "вперед":
            return .moveForward
        case "backward", "move_backward", "назад":
            return .moveBackward
        case "left", "move_left", "влево":
            return .moveLeft
        case "right", "move_right", "вправо":
            return .moveRight
        case "action", "primary", "e", "действие":
            return .primaryAction
        case "force", "f", "удар":
            return .forceAction
        case "throw", "space", "бросок":
            return .throwObject
        case "describe", "q", "описание":
            return .describeFocus
        case "place", "hold_e", "положить":
            return .placeHeldItem
        case "inventory", "i", "inv", "esc", "escape":
            return .inventoryToggle
        case "inventory_quick", "inventory_place", "c":
            return .inventoryQuickAction
        case "location_menu", "beacon", "x":
            return .locationMenuToggle
        case "location_confirm", "enter", "return":
            return .locationMenuConfirm
        default:
            return nil
        }
    }
}

enum KeyboardInputEvent {
    case press(GameCommand)
    case release(GameCommand)
    case command(GameCommand)
}

struct PlatformButtonDefinition: Identifiable {
    let command: GameCommand
    let title: String
    let hint: String

    var id: String {
        command.rawValue + "." + title
    }
}

struct PlatformControls {
    let macKeyboardHintsOnce: [String]
    let iphoneButtons: [PlatformButtonDefinition]
    let shouldSpeakControlNames: Bool

    static var current: PlatformControls {
        #if os(macOS)
        return PlatformControls(
            macKeyboardHintsOnce: [
                "Стрелки двигают тебя по комнате в четыре стороны.",
                "Клавиша Q читает полное описание текущего объекта.",
                "Клавиша E делает главное действие.",
                "Клавиша F бьет или ломает.",
                "Пробел сбрасывает или отталкивает.",
                "Удержание E кладет предмет обратно."
            ],
            iphoneButtons: [],
            shouldSpeakControlNames: true
        )
        #else
        return PlatformControls(
            macKeyboardHintsOnce: [],
            iphoneButtons: [
                PlatformButtonDefinition(command: .moveForward, title: "Идти", hint: "Шаг вперед"),
                PlatformButtonDefinition(command: .moveBackward, title: "Назад", hint: "Шаг назад"),
                PlatformButtonDefinition(command: .moveLeft, title: "Влево", hint: "Шаг влево"),
                PlatformButtonDefinition(command: .moveRight, title: "Вправо", hint: "Шаг вправо"),
                PlatformButtonDefinition(command: .describeFocus, title: "Описание", hint: "Полное описание")
            ],
            shouldSpeakControlNames: false
        )
        #endif
    }
}
