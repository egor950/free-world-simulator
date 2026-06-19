import Foundation
import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {
    let ui = GameUIState()

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
    let navigationBeaconState = NavigationBeaconState()
    let neighbor = NeighborSystem()
    let doors = DoorSystem()
    let groceryStoreClerkMachine = GroceryStoreClerkMachine()
    let roomTraversalMachine = RoomTraversalMachine()
    let poseMachine = PoseMachine()
    let inventoryMachine = InventoryMachine()
    let vehicleRuntime = GameVehicleRuntime()
    var lastMovementAt: Date = .distantPast
    var bedAnchorPosition: GridPosition?

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
        self.ui.stage = flowController.currentStage
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

        self.ui.statusText = """
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
            guard self.ui.stage == .exploration, self.currentRoom.id == .street else { return }
            let text = "Во дворе припарковалась \(snapshot.title)."
            self.addLog(text)
            self.announce(text)
        }

        self.neighbor.delegate = self
        self.doors.delegate = self

        refreshScreenState()
    }
}

// MARK: - NeighborDelegate

extension GameViewModel: NeighborDelegate {
    var currentStage: GameStage { ui.stage }
}

// MARK: - DoorDelegate

@MainActor
extension GameViewModel: DoorDelegate {
    func announce(_ text: String) {
        announce(text, delay: 0)
    }

    func refreshScreenState() {
        refreshScreenState(syncAudio: true)
    }

    func doorLinkID(for door: DoorDefinition) -> String {
        let ids = [state.player.roomID.rawValue, door.targetRoomID.rawValue].sorted()
        return ids.joined(separator: "|")
    }

    func doorMachine(for door: DoorDefinition) -> DoorLifecycleMachine {
        let linkID = doorLinkID(for: door)
        if let machine = doors.doorLifecycleMachines[linkID] {
            machine.sync(staticState: door.state)
            return machine
        }
        let machine = DoorLifecycleMachine(staticState: door.state)
        doors.doorLifecycleMachines[linkID] = machine
        return machine
    }
}
