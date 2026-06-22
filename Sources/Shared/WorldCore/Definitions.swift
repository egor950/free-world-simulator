import Foundation

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

    var closeSound: AudioCueID {
        sound ?? .obstacleThud
    }

    var openSound: AudioCueID {
        switch id {
        case "bedroom.door.hallway", "bedroom.door.livingRoom":
            return .doorOpenBedroom
        case "livingRoom.door.bedroom", "livingRoom.door.kitchen":
            return .doorOpenLivingRoom
        case "kitchen.door.livingRoom", "kitchen.door.teaRoom":
            return .doorOpenKitchen
        case "bathroom.door.street", "bathroom.door.teaRoom":
            return .doorOpenBathroom
        case "teaRoom.door.kitchen", "teaRoom.door.bathroom":
            return .doorOpenTeaRoom
        case "hallway.door.bedroom", "hallway.door.storage", "hallway.door.neighbors":
            return .doorOpenHallway
        default:
            return .doorOpenHallway
        }
    }
}

struct ItemAction {
    let trigger: ActionTrigger
    let title: String
    let resultText: String
    let sound: AudioCueID?
    let requiresHeldItemID: String?
    let requiresEmptyHandsMessage: String?
    let producesHeldItem: HeldItem?
    let interactionID: String?
    let stateMutation: (inout WorldRuntimeState) -> Void

    init(
        trigger: ActionTrigger,
        title: String,
        resultText: String,
        sound: AudioCueID?,
        requiresHeldItemID: String?,
        requiresEmptyHandsMessage: String? = nil,
        producesHeldItem: HeldItem?,
        interactionID: String? = nil,
        stateMutation: @escaping (inout WorldRuntimeState) -> Void
    ) {
        self.trigger = trigger
        self.title = title
        self.resultText = resultText
        self.sound = sound
        self.requiresHeldItemID = requiresHeldItemID
        self.requiresEmptyHandsMessage = requiresEmptyHandsMessage
        self.producesHeldItem = producesHeldItem
        self.interactionID = interactionID
        self.stateMutation = stateMutation
    }
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
