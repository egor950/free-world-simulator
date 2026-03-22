import Foundation
import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {
    enum NeighborNoise {
        static let worldID = "world.neighborNoise"
        static let warnedFlag = "warned"
        static let doorbellFlag = "doorbell"
        static let bangingFlag = "banging"
        static let resolvedFlag = "resolved"
    }

    @Published var stage: GameStage
    @Published var selectedCharacterKind: CharacterKind = .man
    @Published var characterName: String = ""

    @Published var statusText: String
    @Published var roomTitle: String = ""
    @Published var focusTitle: String = ""
    @Published var focusShortText: String = ""
    @Published var holdText: String = ""
    @Published var eventLog: [String] = []
    @Published var tutorialText: String = ""
    @Published var isTutorialVisible: Bool = false
    @Published var isInventoryOpen: Bool = false
    @Published var inventoryTitle: String = ""
    @Published var inventoryText: String = ""

    let platformControls = PlatformControls.current
    let speechCoordinator: SpeechCoordinator
    let audioCoordinator: AudioCoordinator
    let flowController: GameFlowController
    let rooms: [RoomID: RoomDefinition]
    let tutorialDefaultsKey: String
    let movementStepInterval: TimeInterval
    let onLogLine: ((String) -> Void)?
    let onGameFinished: (() -> Void)?

    var state: WorldRuntimeState
    var pendingAnnouncementTask: Task<Void, Never>?
    var pendingStreetCarDepartureTask: Task<Void, Never>?
    var neighborResponseTask: Task<Void, Never>?
    var neighborBreakInTask: Task<Void, Never>?
    var lastMovementAt: Date = .distantPast
    var bedAnchorPosition: GridPosition?
    var openedDoorLinks: Set<String> = []
    var neighborDoorHitsTarget = 0
    var neighborDoorHitsDone = 0
    var streetCarSnapshots: [StreetTrafficCoordinator.StreetCarSnapshot] = []

    init(
        speechCoordinator: SpeechCoordinator? = nil,
        audioCoordinator: AudioCoordinator? = nil,
        flowController: GameFlowController = GameFlowController(),
        movementStepInterval: TimeInterval = 0.28,
        onLogLine: ((String) -> Void)? = nil,
        onGameFinished: (() -> Void)? = nil
    ) {
        self.speechCoordinator = speechCoordinator ?? SpeechCoordinator()
        self.audioCoordinator = audioCoordinator ?? AudioCoordinator()
        self.flowController = flowController
        self.rooms = WorldBuilder.makeWorld()
        self.movementStepInterval = movementStepInterval
        self.onLogLine = onLogLine
        self.onGameFinished = onGameFinished
        self.stage = flowController.currentStage
        self.tutorialDefaultsKey = platformControls.shouldSpeakControlNames
            ? "freeworld.tutorial.mac"
            : "freeworld.tutorial.iphone"

        let initialRoom = rooms[.hallway] ?? WorldBuilder.makeWorld()[.hallway]!
        self.state = WorldRuntimeState(
            player: PlayerState(
                roomID: .hallway,
                roomPosition: initialRoom.spawnPosition,
                focusedTarget: .none,
                pose: .standing,
                heldItem: nil,
                hasCompletedTutorial: UserDefaults.standard.bool(forKey: tutorialDefaultsKey)
            )
        )

        self.statusText = """
        Добро пожаловать в игру «Симулятор свободного мира».
        Здесь мы исследуем квартиру, подходим к дверям и предметам, а длинные описания слушаем отдельно.
        """

        self.audioCoordinator.setStreetCarObserver { [weak self] snapshots in
            guard let self else { return }
            self.streetCarSnapshots = snapshots
            if self.currentRoom.id == .street {
                self.refreshScreenState()
            }
        }
        self.audioCoordinator.setStreetParkingObserver { [weak self] snapshot in
            guard let self else { return }
            guard self.stage == .exploration, self.currentRoom.id == .street else { return }
            let text = "Во дворе припарковалась \(snapshot.title)."
            self.addLog(text)
            self.announce(text)
        }

        refreshScreenState()
    }

    var canFinishCharacterCreation: Bool {
        !characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentCharacterSummary: String {
        let safeName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeName.isEmpty {
            return "Имя пока не введено"
        }
        return "\(selectedCharacterKind.rawValue), \(safeName)"
    }

    var movementButtons: [PlatformButtonDefinition] {
        [
            PlatformButtonDefinition(command: .moveLeft, title: "Влево", hint: "Шаг влево"),
            PlatformButtonDefinition(command: .moveForward, title: "Идти", hint: "Шаг вперед"),
            PlatformButtonDefinition(command: .moveRight, title: "Вправо", hint: "Шаг вправо"),
            PlatformButtonDefinition(command: .moveBackward, title: "Назад", hint: "Шаг назад")
        ]
    }

    var actionButtons: [PlatformButtonDefinition] {
        if isInventoryOpen {
            return inventoryButtons
        }

        var buttons: [PlatformButtonDefinition] = []

        if let action = currentFocusDoor {
            buttons.append(
                PlatformButtonDefinition(
                    command: .primaryAction,
                    title: doorActionTitle(for: action),
                    hint: "Действие у двери"
                )
            )
        } else if let action = action(for: .primary) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .primaryAction,
                    title: action.title,
                    hint: "Главное действие"
                )
            )
        }

        if let action = action(for: .force) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .forceAction,
                    title: action.title,
                    hint: "Силовое действие"
                )
            )
        }

        if let action = action(for: .throwItem) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .throwObject,
                    title: action.title,
                    hint: "Сбросить или оттолкнуть"
                )
            )
        }

        buttons.append(
            PlatformButtonDefinition(
                command: .describeFocus,
                title: "Описание",
                hint: "Полное описание"
            )
        )

        if let action = action(for: .placeHeldItem) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .placeHeldItem,
                    title: action.title,
                    hint: "Положить обратно"
                )
            )
        }

        if state.player.heldItem != nil {
            buttons.append(
                PlatformButtonDefinition(
                    command: .inventoryToggle,
                    title: "Инвентарь",
                    hint: "Открыть предмет в руках"
                )
            )
        }

        return buttons
    }

    var inventoryButtons: [PlatformButtonDefinition] {
        var buttons: [PlatformButtonDefinition] = []

        if let action = heldItemAction(for: .primary) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .primaryAction,
                    title: action.title,
                    hint: "E"
                )
            )
        }

        if let action = heldItemAction(for: .force) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .forceAction,
                    title: action.title,
                    hint: "F"
                )
            )
        }

        if let action = inventoryQuickAction() {
            buttons.append(
                PlatformButtonDefinition(
                    command: .inventoryQuickAction,
                    title: action.title,
                    hint: "C"
                )
            )
        }

        buttons.append(
            PlatformButtonDefinition(
                command: .describeFocus,
                title: "Осмотреть",
                hint: "R"
            )
        )

        buttons.append(
            PlatformButtonDefinition(
                command: .inventoryToggle,
                title: "Закрыть",
                hint: "Escape"
            )
        )

        return buttons
    }

    var debugRoomPosition: GridPosition {
        state.player.roomPosition
    }
}
