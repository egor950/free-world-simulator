@preconcurrency import AVFoundation
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class AudioCoordinator {
    static let defaultGlobalReverbPreset: AVAudioUnitReverbPreset = .largeHall
    static let defaultGlobalReverbWetDryMix: Float = 0

    enum StreetPresence: Equatable {
        case off
        case insideClosedDoor
        case insideOpenDoor
        case courtyard
        case outside
        case wideOpenStreet
    }

    let isMuted: Bool
    var isMuffled: Bool = false
    let effectEngine = AVAudioEngine()
    let environmentNode = AVAudioEnvironmentNode()
    let effectReverb = AVAudioUnitReverb()
    let preStunMixer = AVAudioMixerNode()
    let effectOnlyMixer = AVAudioMixerNode()
    let streetBedPlayer = AVAudioPlayerNode()
    let streetBedEQ = AVAudioUnitEQ(numberOfBands: 1)

    var ambientPlayer: AVAudioPlayer?
    var activeEffects: [AVAudioPlayer] = []
    var activeEngineEffects: [AVAudioPlayerNode] = []
    var activeSpatialPlayers: [AVAudioPlayerNode] = []

    var ambientCue: AudioCueID?
    var currentStepSurface: StepSurface = .carpet
    var lastAsphaltStep: AudioCueID?
    var streetBedBuffer: AVAudioPCMBuffer?
    var streetPresence: StreetPresence = .off
    var streetBedTransitionTask: Task<Void, Never>?
    var streetTraffic: StreetTrafficCoordinator?
    let playerCarAudioRuntime = PlayerCarAudioRuntime()
    let parkedOwnedCarAudioRuntime = ParkedOwnedCarAudioRuntime()
    var cueDurationCache: [AudioCueID: TimeInterval] = [:]
    var kettleSwitchPlayer: AVAudioPlayer?
    var kettleHeatStartPlayer: AVAudioPlayer?
    var kettleHeatLoopPlayer: AVAudioPlayer?
    var kettleHeatFinishPlayer: AVAudioPlayer?
    var kettleHeatLoopStartTask: Task<Void, Never>?
    var navigationMarkerPlayers: [AVAudioPlayer] = []
    var hallwayReverbEnabled: Bool = false

    // MARK: - Stun Effect
    var isStunned: Bool = false
    var stunRecoveryTask: Task<Void, Never>?
    let stunReverb = AVAudioUnitReverb()
    let stunEQ = AVAudioUnitEQ(numberOfBands: 1)
    var stunHeartbeatPlayer: AVAudioPlayer?
    var savedAmbientVolume: Float = 0
    var stunOutdoorDuckingMultiplier: Float = 1.0

    init(isMuted: Bool = false) {
        self.isMuted = isMuted
        activateAudioSessionIfNeeded()
        configureAudioEngine()
        streetTraffic = StreetTrafficCoordinator(
            effectEngine: effectEngine,
            stunInputMixer: preStunMixer,
            resourceURLProvider: { [weak self] cue in
                self?.resourceURL(for: cue)
            }
        )
    }

    func setStepSurface(_ surface: StepSurface) {
        currentStepSurface = surface
    }

    func setTrafficEnabled(_ enabled: Bool) {
        guard !isMuted else { return }
        streetTraffic?.setEnabled(enabled)
    }

    func setStreetListenerPosition(_ position: GridPosition, roomID: RoomID = .street) {
        streetTraffic?.setListenerStreetPosition(position, roomID: roomID)
    }

    func triggerStreetCarDeparture(_ id: UUID) {
        streetTraffic?.triggerDeparture(for: id)
    }

    func setStreetCarObserver(_ observer: (([StreetTrafficCoordinator.StreetCarSnapshot]) -> Void)?) {
        streetTraffic?.onStreetCarsChanged = observer
    }

    func setStreetParkingObserver(_ observer: ((StreetTrafficCoordinator.StreetCarSnapshot) -> Void)?) {
        streetTraffic?.onStreetCarParked = observer
    }

    func runStreetDebugScenario(_ rawName: String) -> Bool {
        guard let scenario = StreetTrafficCoordinator.DebugScenario(rawValue: rawName) else {
            return false
        }

        streetTraffic?.runDebugScenario(scenario)
        return true
    }

    func clearStreetDebugScenario() {
        streetTraffic?.clearDebugScenario()
    }

    func streetDebugSnapshotPayload() -> [[String: Any]] {
        streetTraffic?.debugSnapshotPayload() ?? []
    }
}
