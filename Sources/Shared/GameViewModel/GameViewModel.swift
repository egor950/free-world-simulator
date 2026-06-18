import Foundation
import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {
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
    @Published var isLocationMenuOpen: Bool = false
    @Published var locationMenuTitle: String = ""
    @Published var locationMenuText: String = ""

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
    var kettleBoilingTask: Task<Void, Never>?
    var neighborResponseTask: Task<Void, Never>?
    var neighborBreakInTask: Task<Void, Never>?
    var navigationBeaconTask: Task<Void, Never>?
    var activeNavigationBeaconID: String?
    var selectedLocationMenuIndex: Int = 0
    lazy var neighborEncounterMachine = NeighborEncounterMachine()
    let groceryStoreClerkMachine = GroceryStoreClerkMachine()
    let roomTraversalMachine = RoomTraversalMachine()
    let poseMachine = PoseMachine()
    let inventoryMachine = InventoryMachine()
    let vehicleRuntime = GameVehicleRuntime()
    var lastMovementAt: Date = .distantPast
    var bedAnchorPosition: GridPosition?
    var doorLifecycleMachines: [String: DoorLifecycleMachine] = [:]
    var gateLifecycleMachines: [String: GateLifecycleMachine] = [:]
    var gateTransitionTasks: [String: Task<Void, Never>] = [:]
    var neighborDoorHitsTarget = 0
    var debugNeighborResponsePauseRange: ClosedRange<Double>?
    var debugNeighborBreakInPauseRange: ClosedRange<Double>?
    var debugNeighborDoorHitsTargetOverride: Int?
    var debugNeighborFootstepCountOverride: Int?
    var debugNeighborFootstepPauseOverride: TimeInterval?

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
            if self.currentRoom.id == .street, self.state.controlledCar == nil {
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
}
