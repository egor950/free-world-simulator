@preconcurrency import AVFoundation
import Foundation
import GameplayKit

@MainActor
final class StreetTrafficCoordinator {
    static let desiredMinimumTrafficCount = 2
    static let maximumTrafficCount = 4
    enum DebugScenario: String, CaseIterable {
        case parkedCar = "street_parked_car"
        case approachingCar = "street_approaching_car"
        case departingCar = "street_departing_car"
        case mainStreetEntryLeft = "main_street_car_entry_left"
        case mainStreetEntryRight = "main_street_car_entry_right"
        case mainStreetExit = "main_street_car_exit"
    }

    struct StreetCarSnapshot: Equatable {
        let id: UUID
        let title: String
        let shortPrompt: String
        let fullDescription: String
        let position: GridPosition
        let worldPosition: OutdoorCarWorldPosition
        let directionLeftToRight: Bool
        let vehicleKind: DriveableVehicleKind
        let isParked: Bool
        let isInspectable: Bool
    }

    struct TrafficProfile {
        let cue: AudioCueID
        let cruiseRateRange: ClosedRange<Float>
        let brakeDepthRange: ClosedRange<Float>
        let volumeBoost: Float
        let roadPassSpeedRange: ClosedRange<Float>
        let slowRollSpeedRange: ClosedRange<Float>
        let parkingSpeedRange: ClosedRange<Float>
        let accelerationScale: Float
        let brakeScale: Float
        let idleEngineHz: Double
        let maxEngineHz: Double
        let gearShiftEngineHz: Double
        let gearCount: Int
    }

    enum TrafficRouteStyle {
        case roadPass
        case courtyardParking
        case slowRollBy
    }

    enum TrafficDistanceBand: CaseIterable {
        case close
        case medium
        case far

        var volumeMultiplier: Float {
            switch self {
            case .close:
                return 1.35
            case .medium:
                return 1.0
            case .far:
                return 0.78
            }
        }
    }

    enum TrafficSpeedBand: CaseIterable {
        case slow
        case normal
        case fast
    }

    struct TrafficObject {
        let id: UUID
        let profile: TrafficProfile
        let speedBand: TrafficSpeedBand
        let directionLeftToRight: Bool
        let routeStyle: TrafficRouteStyle
        let courtyardAccessPlan: CourtyardAccessPlan?
        let startPhase: TrafficLifecycle.StartPhase
        let baseVolume: Float
        let toneOffset: Float
        let sampleRate: Double
        let startX: Float
        let startZ: Float
        let endX: Float
        let finalExitX: Float
        let roadZ: Float
        let nearZ: Float
        let entrySpeed: Float
        let cruiseSpeed: Float
        let maxSpeed: Float
        let acceleration: Float
        let brakeDeceleration: Float
        let rollingDeceleration: Float
        let dragFactor: Float
        let brakeTargetSpeed: Float
        let brakeCenterX: Float
        let brakeHalfWidth: Float
        let parkHoldDuration: Float
    }

    struct TrafficEngineTuning {
        let idleHz: Double
        let topHz: Double
        let shiftHz: Double
        let gears: Int
    }

    struct TrafficAudioUnit {
        let player: AVAudioPlayerNode
        let brakePlayer: AVAudioPlayerNode?
        let varispeed: AVAudioUnitVarispeed
        let eq: AVAudioUnitEQ
        let panner: AVAudioMixerNode
    }

    final class TrafficLifecycle {
        enum StartPhase {
            case passing
            case streetApproach
            case courtyardEntry
            case courtyardCruise
            case parked
            case courtyardExit
            case streetDeparture
        }

        private final class PassingState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == FinishedState.self
            }
        }

        private final class StreetApproachState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == CourtyardEntryState.self || stateClass == FinishedState.self
            }
        }

        private final class CourtyardEntryState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == CourtyardCruiseState.self || stateClass == FinishedState.self
            }
        }

        private final class CourtyardCruiseState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == ParkedState.self || stateClass == FinishedState.self
            }
        }

        private final class ParkedState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == CourtyardExitState.self || stateClass == FinishedState.self
            }
        }

        private final class CourtyardExitState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == StreetDepartureState.self || stateClass == FinishedState.self
            }
        }

        private final class StreetDepartureState: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                stateClass == FinishedState.self
            }
        }

        private final class FinishedState: GKState {}

        private let routeStyle: TrafficRouteStyle
        private let machine: GKStateMachine

        private(set) var parkedElapsed: Float = 0
        private(set) var departureElapsed: Float = 0
        private(set) var completedParkingStop = false

        init(routeStyle: TrafficRouteStyle, startPhase: StartPhase = .passing) {
            self.routeStyle = routeStyle
            switch routeStyle {
            case .courtyardParking:
                machine = GKStateMachine(states: [
                    StreetApproachState(),
                    CourtyardEntryState(),
                    CourtyardCruiseState(),
                    ParkedState(),
                    CourtyardExitState(),
                    StreetDepartureState(),
                    FinishedState()
                ])
                switch startPhase {
                case .passing, .streetApproach:
                    machine.enter(StreetApproachState.self)
                case .courtyardEntry:
                    machine.enter(CourtyardEntryState.self)
                case .courtyardCruise:
                    machine.enter(CourtyardCruiseState.self)
                case .parked:
                    completedParkingStop = true
                    machine.enter(ParkedState.self)
                case .courtyardExit:
                    completedParkingStop = true
                    machine.enter(CourtyardExitState.self)
                case .streetDeparture:
                    completedParkingStop = true
                    machine.enter(StreetDepartureState.self)
                }
            case .roadPass, .slowRollBy:
                machine = GKStateMachine(states: [
                    PassingState(),
                    FinishedState()
                ])
                machine.enter(PassingState.self)
            }
        }

        var isParkingRoute: Bool {
            routeStyle == .courtyardParking
        }

        var isStreetApproach: Bool {
            machine.currentState is StreetApproachState
        }

        var isCourtyardEntry: Bool {
            machine.currentState is CourtyardEntryState
        }

        var isCourtyardCruise: Bool {
            machine.currentState is CourtyardCruiseState
        }

        var isApproachingParkingSpot: Bool {
            isCourtyardEntry || isCourtyardCruise
        }

        var isParked: Bool {
            machine.currentState is ParkedState
        }

        var isCourtyardExit: Bool {
            machine.currentState is CourtyardExitState
        }

        var isStreetDeparture: Bool {
            machine.currentState is StreetDepartureState
        }

        var isDeparting: Bool {
            isCourtyardExit || isStreetDeparture
        }

        var didCompleteParkingStop: Bool {
            completedParkingStop
        }

        func advance(deltaTime: Float, parkHoldDuration: Float) {
            if isParked {
                parkedElapsed += deltaTime
                if parkedElapsed >= parkHoldDuration, beginDeparture() {
                    departureElapsed += deltaTime
                }
                return
            }

            if isDeparting {
                departureElapsed += deltaTime
            }
        }

        @discardableResult
        func beginParked() -> Bool {
            guard isParkingRoute, isApproachingParkingSpot else {
                return false
            }

            guard machine.enter(ParkedState.self) else {
                return false
            }

            parkedElapsed = 0
            departureElapsed = 0
            return true
        }

        @discardableResult
        func beginDeparture() -> Bool {
            guard isParkingRoute, isParked else {
                return false
            }

            guard machine.enter(CourtyardExitState.self) else {
                return false
            }

            completedParkingStop = true
            parkedElapsed = 0
            departureElapsed = 0
            return true
        }

        func forceDepartureIfNeeded(for id: UUID, forcedIDs: inout Set<UUID>, deltaTime: Float) {
            guard isParked, forcedIDs.contains(id) else {
                return
            }

            forcedIDs.remove(id)
            if beginDeparture() {
                departureElapsed += deltaTime
            }
        }

        @discardableResult
        func beginCourtyardEntry() -> Bool {
            guard isParkingRoute, isStreetApproach else {
                return false
            }
            return machine.enter(CourtyardEntryState.self)
        }

        @discardableResult
        func beginCourtyardCruise() -> Bool {
            guard isParkingRoute, isCourtyardEntry else {
                return false
            }
            return machine.enter(CourtyardCruiseState.self)
        }

        @discardableResult
        func beginStreetDeparture() -> Bool {
            guard isParkingRoute, isCourtyardExit else {
                return false
            }
            return machine.enter(StreetDepartureState.self)
        }

        func markFinished() {
            _ = machine.enter(FinishedState.self)
        }
    }

    let effectEngine: AVAudioEngine
    let resourceURLProvider: (AudioCueID) -> URL?

    var onStreetCarsChanged: (([StreetCarSnapshot]) -> Void)?
    var onStreetCarParked: ((StreetCarSnapshot) -> Void)?

    var activeTrafficPlayers: [UUID: TrafficAudioUnit] = [:]
    var activeTrafficTasks: [UUID: Task<Void, Never>] = [:]
    var activeTrafficRoutes: [UUID: TrafficRouteStyle] = [:]
    var activeTrafficCues: [UUID: AudioCueID] = [:]
    var activeTrafficSpeedBands: [UUID: TrafficSpeedBand] = [:]
    var activeCourtyardParkingIDs: Set<UUID> = []
    var trafficBufferCache: [AudioCueID: AVAudioPCMBuffer] = [:]
    var brakeBuffer: AVAudioPCMBuffer?
    var trafficLoopTask: Task<Void, Never>?
    var isEnabled = false
    var lastCourtyardParkingCue: AudioCueID?
    let parkingSpawnDirector = ParkingSpawnDirector()
    var listenerStreetPosition = GridPosition(x: 7, y: 14)
    var listenerOutdoorRoomID: RoomID = .street
    var forcedDepartureIDs: Set<UUID> = []
    var activeDebugScenario: DebugScenario?
    var activeStreetCarSnapshots: [UUID: StreetCarSnapshot] = [:] {
        didSet {
            guard activeStreetCarSnapshots != oldValue else { return }
            let snapshots = activeStreetCarSnapshots.values.sorted { lhs, rhs in
                if lhs.position.y == rhs.position.y {
                    return lhs.position.x < rhs.position.x
                }
                return lhs.position.y < rhs.position.y
            }
            onStreetCarsChanged?(snapshots)
        }
    }

    init(
        effectEngine: AVAudioEngine,
        resourceURLProvider: @escaping (AudioCueID) -> URL?
    ) {
        self.effectEngine = effectEngine
        self.resourceURLProvider = resourceURLProvider
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            parkingSpawnDirector.reset(initiallyReady: false)
            if let scenario = activeDebugScenario {
                if activeTrafficPlayers.isEmpty {
                    runDebugScenarioInternal(scenario)
                }
            } else {
                startLoop()
            }
        } else {
            stopLoop()
        }
    }

    func setListenerStreetPosition(_ position: GridPosition, roomID: RoomID = .street) {
        listenerStreetPosition = position
        listenerOutdoorRoomID = roomID
    }

    func triggerDeparture(for carID: UUID) {
        forcedDepartureIDs.insert(carID)
    }

    func runDebugScenario(_ scenario: DebugScenario) {
        activeDebugScenario = scenario
        isEnabled = true
        stopLoop()
        runDebugScenarioInternal(scenario)
    }

    func clearDebugScenario() {
        activeDebugScenario = nil
        stopLoop()
        if isEnabled {
            startLoop()
        }
    }

    func debugSnapshotPayload() -> [[String: Any]] {
        activeStreetCarSnapshots.values.sorted { lhs, rhs in
            if lhs.position.y == rhs.position.y {
                return lhs.position.x < rhs.position.x
            }
            return lhs.position.y < rhs.position.y
        }.map { snapshot in
            [
                "id": snapshot.id.uuidString,
                "title": snapshot.title,
                "shortPrompt": snapshot.shortPrompt,
                "x": snapshot.position.x,
                "y": snapshot.position.y,
                "worldX": snapshot.worldPosition.x,
                "worldZ": snapshot.worldPosition.z,
                "vehicleKind": snapshot.vehicleKind.rawValue,
                "directionLeftToRight": snapshot.directionLeftToRight,
                "isParked": snapshot.isParked,
                "isInspectable": snapshot.isInspectable
            ]
        }
    }

    func claimParkedCar(id: UUID) -> StreetCarSnapshot? {
        guard let snapshot = activeStreetCarSnapshots[id], snapshot.isParked else {
            return nil
        }

        if let task = activeTrafficTasks.removeValue(forKey: id) {
            task.cancel()
        }
        activeTrafficRoutes.removeValue(forKey: id)
        activeTrafficCues.removeValue(forKey: id)
        activeTrafficSpeedBands.removeValue(forKey: id)
        activeCourtyardParkingIDs.remove(id)
        forcedDepartureIDs.remove(id)
        clearStreetCarSnapshot(for: id)
        return snapshot
    }

}
