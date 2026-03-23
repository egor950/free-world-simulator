import Foundation
import GameplayKit
import SwiftUI

final class DoorLifecycleMachine {
    private final class LockedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            false
        }
    }

    private final class ClosedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpenState.self || stateClass == LockedState.self
        }
    }

    private final class OpenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ClosedState.self || stateClass == LockedState.self
        }
    }

    private let machine: GKStateMachine

    init(staticState: DoorState) {
        machine = GKStateMachine(states: [
            LockedState(),
            ClosedState(),
            OpenState()
        ])
        sync(staticState: staticState)
    }

    var isLocked: Bool {
        machine.currentState is LockedState
    }

    var isOpen: Bool {
        machine.currentState is OpenState
    }

    func sync(staticState: DoorState) {
        switch staticState {
        case .locked:
            _ = machine.enter(LockedState.self)
        case .closed:
            if machine.currentState == nil {
                _ = machine.enter(ClosedState.self)
            }
        }
    }

    @discardableResult
    func open() -> Bool {
        guard !isLocked else { return false }
        return machine.enter(OpenState.self)
    }

    @discardableResult
    func close() -> Bool {
        guard !isLocked else { return false }
        return machine.enter(ClosedState.self)
    }
}

final class RoomTraversalMachine {
    private final class LinearTraversalState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == GridTraversalState.self
        }
    }

    private final class GridTraversalState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == LinearTraversalState.self
        }
    }

    private let machine = GKStateMachine(states: [
        LinearTraversalState(),
        GridTraversalState()
    ])

    init(initialMode: RoomMovementMode = .linearPath) {
        sync(mode: initialMode)
    }

    var isLinearTraversal: Bool {
        machine.currentState is LinearTraversalState
    }

    var isGridTraversal: Bool {
        machine.currentState is GridTraversalState
    }

    func sync(mode: RoomMovementMode) {
        switch mode {
        case .linearPath:
            _ = machine.enter(LinearTraversalState.self)
        case .freeGrid4Way:
            _ = machine.enter(GridTraversalState.self)
        }
    }
}

final class PoseMachine {
    private final class StandingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == LyingState.self || stateClass == CrawlingState.self
        }
    }

    private final class LyingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == StandingState.self || stateClass == CrawlingState.self
        }
    }

    private final class CrawlingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == StandingState.self || stateClass == LyingState.self
        }
    }

    private let machine = GKStateMachine(states: [
        StandingState(),
        LyingState(),
        CrawlingState()
    ])

    init(initialPose: PlayerPose = .standing) {
        sync(pose: initialPose)
    }

    var isStanding: Bool {
        machine.currentState is StandingState
    }

    var isLying: Bool {
        machine.currentState is LyingState
    }

    var isCrawling: Bool {
        machine.currentState is CrawlingState
    }

    func sync(pose: PlayerPose) {
        switch pose {
        case .standing:
            _ = machine.enter(StandingState.self)
        case .lying:
            _ = machine.enter(LyingState.self)
        case .crawling:
            _ = machine.enter(CrawlingState.self)
        }
    }
}

final class InventoryMachine {
    private final class ClosedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpenState.self
        }
    }

    private final class OpenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ClosedState.self
        }
    }

    private let machine = GKStateMachine(states: [
        ClosedState(),
        OpenState()
    ])

    init(isOpen: Bool = false) {
        sync(isOpen: isOpen)
    }

    var isOpen: Bool {
        machine.currentState is OpenState
    }

    func sync(isOpen: Bool) {
        if isOpen {
            _ = machine.enter(OpenState.self)
        } else {
            _ = machine.enter(ClosedState.self)
        }
    }

    @discardableResult
    func open() -> Bool {
        machine.enter(OpenState.self)
    }

    @discardableResult
    func close() -> Bool {
        machine.enter(ClosedState.self)
    }
}

final class BreakableItemMachine {
    enum Stage: String {
        case intact
        case broken
    }

    private final class IntactState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == BrokenState.self
        }
    }

    private final class BrokenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IntactState.self
        }
    }

    private let machine = GKStateMachine(states: [
        IntactState(),
        BrokenState()
    ])

    init(stage: Stage = .intact) {
        sync(stage: stage)
    }

    var stage: Stage {
        machine.currentState is BrokenState ? .broken : .intact
    }

    var isBroken: Bool {
        stage == .broken
    }

    func sync(stage: Stage) {
        switch stage {
        case .intact:
            _ = machine.enter(IntactState.self)
        case .broken:
            _ = machine.enter(BrokenState.self)
        }
    }

    @discardableResult
    func markBroken() -> Bool {
        machine.enter(BrokenState.self)
    }
}

final class PillowConditionMachine {
    enum Stage: String {
        case intact
        case dusty
        case torn
    }

    private final class IntactState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == DustyState.self || stateClass == TornState.self
        }
    }

    private final class DustyState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == TornState.self || stateClass == IntactState.self
        }
    }

    private final class TornState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IntactState.self
        }
    }

    private let machine = GKStateMachine(states: [
        IntactState(),
        DustyState(),
        TornState()
    ])

    init(stage: Stage = .intact) {
        sync(stage: stage)
    }

    var stage: Stage {
        switch machine.currentState {
        case is DustyState:
            return .dusty
        case is TornState:
            return .torn
        default:
            return .intact
        }
    }

    func sync(stage: Stage) {
        switch stage {
        case .intact:
            _ = machine.enter(IntactState.self)
        case .dusty:
            _ = machine.enter(DustyState.self)
        case .torn:
            _ = machine.enter(TornState.self)
        }
    }

    @discardableResult
    func markDusty() -> Bool {
        machine.enter(DustyState.self)
    }

    @discardableResult
    func markTorn() -> Bool {
        machine.enter(TornState.self)
    }
}

final class PillowPlacementMachine {
    enum Stage {
        case onBed
        case held
        case onFloor
    }

    private final class OnBedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == HeldState.self || stateClass == OnFloorState.self
        }
    }

    private final class HeldState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OnBedState.self || stateClass == OnFloorState.self
        }
    }

    private final class OnFloorState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == HeldState.self || stateClass == OnBedState.self
        }
    }

    private let machine = GKStateMachine(states: [
        OnBedState(),
        HeldState(),
        OnFloorState()
    ])

    init(stage: Stage = .onBed) {
        sync(stage: stage)
    }

    var stage: Stage {
        switch machine.currentState {
        case is HeldState:
            return .held
        case is OnFloorState:
            return .onFloor
        default:
            return .onBed
        }
    }

    var isHeld: Bool {
        stage == .held
    }

    var isOnFloor: Bool {
        stage == .onFloor
    }

    func sync(stage: Stage) {
        switch stage {
        case .onBed:
            _ = machine.enter(OnBedState.self)
        case .held:
            _ = machine.enter(HeldState.self)
        case .onFloor:
            _ = machine.enter(OnFloorState.self)
        }
    }

    @discardableResult
    func markOnBed() -> Bool {
        machine.enter(OnBedState.self)
    }

    @discardableResult
    func markHeld() -> Bool {
        machine.enter(HeldState.self)
    }

    @discardableResult
    func markOnFloor() -> Bool {
        machine.enter(OnFloorState.self)
    }
}

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
    lazy var neighborEncounterMachine = NeighborEncounterMachine()
    let roomTraversalMachine = RoomTraversalMachine()
    let poseMachine = PoseMachine()
    let inventoryMachine = InventoryMachine()
    var lastMovementAt: Date = .distantPast
    var bedAnchorPosition: GridPosition?
    var doorLifecycleMachines: [String: DoorLifecycleMachine] = [:]
    var breakableItemMachines: [String: BreakableItemMachine] = [:]
    let pillowConditionMachine = PillowConditionMachine()
    let pillowPlacementMachine = PillowPlacementMachine()
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
