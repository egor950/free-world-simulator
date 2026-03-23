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
        default:
            return nil
        }
    }
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

enum AudioCueID: String {
    case stepCarpet01
    case stepCarpet02
    case stepAsphalt01
    case stepAsphalt02
    case stepAsphalt03
    case stepAsphalt04
    case stepAsphalt05
    case ambientRoom01
    case cityStreetBed
    case obstacleThud
    case itemPlaceMetal01
    case glassBreakSmall
    case cabinetSmash
    case doorbellMain
    case doorBangingHard
    case doorBreakHeavy
    case gateOpen
    case gateClose
    case punchHit
    case heartbeatFast
    case trafficEngineBase
    case trafficBrakeSoft
    case trafficEngineLight
    case trafficEngineSedan
    case trafficEngineSport
    case trafficEngineCoupe
    case trafficEngineRoadster

    var resourceName: String {
        switch self {
        case .stepCarpet01:
            return "step_carpet_01"
        case .stepCarpet02:
            return "step_carpet_02"
        case .stepAsphalt01:
            return "step_asphalt_01"
        case .stepAsphalt02:
            return "step_asphalt_02"
        case .stepAsphalt03:
            return "step_asphalt_03"
        case .stepAsphalt04:
            return "step_asphalt_04"
        case .stepAsphalt05:
            return "step_asphalt_05"
        case .ambientRoom01:
            return "ambient_room_01"
        case .cityStreetBed:
            return "city_street_bed"
        case .obstacleThud:
            return "item_place_metal_01"
        case .itemPlaceMetal01:
            return "item_place_metal_01"
        case .glassBreakSmall:
            return "glass_break_small"
        case .cabinetSmash:
            return "cabinet_smash"
        case .doorbellMain:
            return "doorbell_main"
        case .doorBangingHard:
            return "door_banging_hard"
        case .doorBreakHeavy:
            return "door_break_heavy"
        case .gateOpen:
            return "gate_open"
        case .gateClose:
            return "gate_close"
        case .punchHit:
            return "punch_hit"
        case .heartbeatFast:
            return "heartbeat_fast"
        case .trafficEngineBase:
            return "traffic_engine_base"
        case .trafficBrakeSoft:
            return "traffic_brake_soft"
        case .trafficEngineLight:
            return "traffic_engine_light"
        case .trafficEngineSedan:
            return "traffic_engine_sedan"
        case .trafficEngineSport:
            return "traffic_engine_sport"
        case .trafficEngineCoupe:
            return "traffic_engine_coupe"
        case .trafficEngineRoadster:
            return "traffic_engine_roadster"
        }
    }

    var fileExtension: String {
        switch self {
        case .stepCarpet01, .stepCarpet02, .stepAsphalt01, .stepAsphalt02, .stepAsphalt03, .stepAsphalt04, .stepAsphalt05, .ambientRoom01, .cityStreetBed:
            return "mp3"
        case .obstacleThud, .itemPlaceMetal01:
            return "m4a"
        case .glassBreakSmall, .cabinetSmash, .doorbellMain, .doorBangingHard, .doorBreakHeavy, .gateOpen, .gateClose, .punchHit, .heartbeatFast, .trafficEngineBase, .trafficBrakeSoft, .trafficEngineLight, .trafficEngineSedan, .trafficEngineSport, .trafficEngineCoupe, .trafficEngineRoadster:
            return "wav"
        }
    }

    var defaultVolume: Float {
        switch self {
        case .ambientRoom01:
            return 0.2
        case .stepCarpet01, .stepCarpet02:
            return 0.6
        case .stepAsphalt01, .stepAsphalt02, .stepAsphalt03, .stepAsphalt04, .stepAsphalt05:
            return 0.78
        case .cityStreetBed:
            return 0.24
        case .obstacleThud:
            return 0.55
        case .itemPlaceMetal01:
            return 0.75
        case .glassBreakSmall:
            return 0.9
        case .cabinetSmash:
            return 0.95
        case .doorbellMain:
            return 0.55
        case .doorBangingHard:
            return 0.72
        case .doorBreakHeavy:
            return 1.08
        case .gateOpen:
            return 0.86
        case .gateClose:
            return 0.84
        case .punchHit:
            return 0.82
        case .heartbeatFast:
            return 0.34
        case .trafficEngineBase:
            return 0.44
        case .trafficBrakeSoft:
            return 0.26
        case .trafficEngineLight:
            return 0.48
        case .trafficEngineSedan:
            return 0.46
        case .trafficEngineSport:
            return 0.4
        case .trafficEngineCoupe:
            return 0.43
        case .trafficEngineRoadster:
            return 0.41
        }
    }

    var loops: Bool {
        self == .ambientRoom01 || self == .heartbeatFast || self == .cityStreetBed
    }
}

struct DoorDefinition {
    let id: String
    let name: String
    let targetRoomID: RoomID
    let targetRoomPosition: GridPosition?
    let state: DoorState
    let focusNodeID: String
    let shortPrompt: String
    let openResultText: String
    let lockedText: String
    let sound: AudioCueID?
    let interactionStyle: DoorInteractionStyle

    init(
        id: String,
        name: String,
        targetRoomID: RoomID,
        targetRoomPosition: GridPosition?,
        state: DoorState,
        focusNodeID: String,
        shortPrompt: String,
        openResultText: String,
        lockedText: String,
        sound: AudioCueID?,
        interactionStyle: DoorInteractionStyle = .standard
    ) {
        self.id = id
        self.name = name
        self.targetRoomID = targetRoomID
        self.targetRoomPosition = targetRoomPosition
        self.state = state
        self.focusNodeID = focusNodeID
        self.shortPrompt = shortPrompt
        self.openResultText = openResultText
        self.lockedText = lockedText
        self.sound = sound
        self.interactionStyle = interactionStyle
    }
}

struct ItemAction {
    let trigger: ActionTrigger
    let title: String
    let resultText: String
    let sound: AudioCueID?
    let requiresHeldItemID: String?
    let producesHeldItem: HeldItem?
    let stateMutation: (inout WorldRuntimeState) -> Void
}

struct ItemDefinition {
    let id: String
    let name: String
    let shortPromptProvider: (WorldRuntimeState) -> String
    let fullDescriptionProvider: (WorldRuntimeState) -> String
    let actionsProvider: (WorldRuntimeState) -> [ItemAction]
}

struct RoomDefinition {
    let id: RoomID
    let title: String
    let entryAnnouncement: String
    let ambientSound: AudioCueID?
    let movementMode: RoomMovementMode
    let stepSurface: StepSurface
    let width: Int
    let height: Int
    let nodes: [FocusNode]
    let doors: [String: DoorDefinition]
    let items: [String: ItemDefinition]
    let spawnPosition: GridPosition

    init(
        id: RoomID,
        title: String,
        entryAnnouncement: String,
        ambientSound: AudioCueID?,
        movementMode: RoomMovementMode = .linearPath,
        stepSurface: StepSurface = .carpet,
        width: Int,
        height: Int,
        nodes: [FocusNode],
        doors: [String: DoorDefinition],
        items: [String: ItemDefinition],
        spawnPosition: GridPosition
    ) {
        self.id = id
        self.title = title
        self.entryAnnouncement = entryAnnouncement
        self.ambientSound = ambientSound
        self.movementMode = movementMode
        self.stepSurface = stepSurface
        self.width = width
        self.height = height
        self.nodes = nodes
        self.doors = doors
        self.items = items
        self.spawnPosition = spawnPosition
    }

    func node(at position: GridPosition) -> FocusNode? {
        nodes.first { $0.position == position }
    }
}

struct PlayerState {
    var roomID: RoomID
    var roomPosition: GridPosition
    var focusedTarget: FocusTarget
    var pose: PlayerPose
    var heldItem: HeldItem?
    var hasCompletedTutorial: Bool
}

struct WorldRuntimeState {
    var player: PlayerState
    private(set) var itemStages: [String: String] = [:]
    private(set) var itemPositions: [String: GridPosition] = [:]
    private(set) var itemRooms: [String: RoomID] = [:]

    func itemStage<Stage: RawRepresentable>(
        itemID: String,
        as type: Stage.Type,
        default defaultValue: Stage
    ) -> Stage where Stage.RawValue == String {
        guard let rawValue = itemStages[itemID],
              let stage = Stage(rawValue: rawValue) else {
            return defaultValue
        }

        return stage
    }

    mutating func setItemStage<Stage: RawRepresentable>(
        itemID: String,
        stage: Stage?
    ) where Stage.RawValue == String {
        itemStages[itemID] = stage?.rawValue
    }

    func position(for itemID: String) -> GridPosition? {
        itemPositions[itemID]
    }

    func room(for itemID: String) -> RoomID? {
        itemRooms[itemID]
    }

    mutating func setItemLocation(itemID: String, roomID: RoomID, position: GridPosition) {
        itemRooms[itemID] = roomID
        itemPositions[itemID] = position
    }

    mutating func clearItemLocation(itemID: String) {
        itemRooms[itemID] = nil
        itemPositions[itemID] = nil
    }
}
