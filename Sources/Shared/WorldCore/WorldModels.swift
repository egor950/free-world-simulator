import Foundation

enum GameStage {
    case welcome
    case characterCreation
    case exploration
    case finished
}

enum CharacterKind: String, CaseIterable, Identifiable {
    case man = "Мужчина"
    case woman = "Женщина"

    var id: String { rawValue }
}

enum RoomID: String, CaseIterable, Identifiable {
    case hallway
    case bedroom
    case livingRoom
    case kitchen
    case bathroom
    case street
    case mainStreet
    case groceryStore
    case teaRoom

    var id: String { rawValue }
}

enum PlayerPose: String {
    case standing
    case lying
    case crawling

    var title: String {
        switch self {
        case .standing:
            return "Стоишь"
        case .lying:
            return "Лежишь"
        case .crawling:
            return "Ползешь"
        }
    }
}

struct HeldItem: Equatable {
    let itemID: String
    let name: String
}

enum FocusTarget: Equatable {
    case door(String)
    case item(String)
    case none
}

struct GridPosition: Equatable {
    let x: Int
    let y: Int
}

enum RoomMovementMode {
    case linearPath
    case freeGrid4Way
}

enum StepSurface {
    case carpet
    case asphalt
}

struct FocusNode {
    let id: String
    let title: String
    let position: GridPosition
    let target: FocusTarget
    let shortPrompt: String?
    let fullDescription: String?

    init(
        id: String,
        title: String,
        position: GridPosition,
        target: FocusTarget,
        shortPrompt: String? = nil,
        fullDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.position = position
        self.target = target
        self.shortPrompt = shortPrompt
        self.fullDescription = fullDescription
    }

    static func floor(id: String, title: String, position: GridPosition, fullDescription: String) -> FocusNode {
        FocusNode(
            id: id,
            title: title,
            position: position,
            target: .none,
            shortPrompt: nil,
            fullDescription: fullDescription
        )
    }
}

enum DoorState {
    case closed
    case locked
}

struct TimedDoorTransitionConfiguration {
    let openCue: AudioCueID
    let closeCue: AudioCueID
    let openDuration: TimeInterval
    let closeDuration: TimeInterval
}

enum DoorInteractionStyle {
    case standard
    case timedGate(TimedDoorTransitionConfiguration)
}

enum ActionTrigger {
    case primary
    case force
    case throwItem
    case describe
    case placeHeldItem
}
