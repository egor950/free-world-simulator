@preconcurrency import AVFoundation
import Foundation

@MainActor
final class ParkedOwnedCarAudioRuntime {
    var player: AVAudioPlayer?
    var activeCarID: UUID?
    var activeCue: AudioCueID?
}

extension AudioCoordinator {
    func syncParkedOwnedCarAudio(
        cars: [ParkedOwnedCarState],
        listenerRoomID: RoomID,
        listenerPosition: GridPosition,
        controlledCar: ControlledCarState?
    ) {
        guard !isMuted else { return }
        guard controlledCar == nil else {
            stopParkedOwnedCarAudio()
            return
        }
        guard listenerRoomID == .street || listenerRoomID == .mainStreet else {
            stopParkedOwnedCarAudio()
            return
        }

        let runningCars = cars.filter { $0.isEngineRunning && $0.roomID == listenerRoomID }
        guard let nearest = runningCars.min(by: {
            manhattanDistance(from: $0.gridPosition, to: listenerPosition) <
            manhattanDistance(from: $1.gridPosition, to: listenerPosition)
        }) else {
            stopParkedOwnedCarAudio()
            return
        }

        let cue = parkedOwnedCarCue(for: nearest.kind)
        if parkedOwnedCarAudioRuntime.activeCarID != nearest.id || parkedOwnedCarAudioRuntime.activeCue != cue {
            startParkedOwnedCarAudio(for: nearest, cue: cue)
        }

        updateParkedOwnedCarAudio(for: nearest, cue: cue, listenerRoomID: listenerRoomID, listenerPosition: listenerPosition)
    }

    func stopParkedOwnedCarAudio() {
        parkedOwnedCarAudioRuntime.player?.stop()
        parkedOwnedCarAudioRuntime.player = nil
        parkedOwnedCarAudioRuntime.activeCarID = nil
        parkedOwnedCarAudioRuntime.activeCue = nil
    }

    private func startParkedOwnedCarAudio(for car: ParkedOwnedCarState, cue: AudioCueID) {
        stopParkedOwnedCarAudio()
        guard let url = resourceURL(for: cue) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.pan = 0
            player.prepareToPlay()
            player.play()
            parkedOwnedCarAudioRuntime.player = player
            parkedOwnedCarAudioRuntime.activeCarID = car.id
            parkedOwnedCarAudioRuntime.activeCue = cue
        } catch {
            parkedOwnedCarAudioRuntime.player = nil
        }
    }

    private func updateParkedOwnedCarAudio(
        for car: ParkedOwnedCarState,
        cue: AudioCueID,
        listenerRoomID: RoomID,
        listenerPosition: GridPosition
    ) {
        guard let player = parkedOwnedCarAudioRuntime.player else { return }

        let listenerPoint = outdoorWorldPoint(for: listenerRoomID, position: listenerPosition)
        let dx = car.worldPosition.x - listenerPoint.x
        let dz = car.worldPosition.z - listenerPoint.z
        let distance = sqrt((dx * dx) + (dz * dz))
        let audibleRadius: Float = listenerRoomID == .street ? 32 : 42
        let distanceMix = max(0, 1 - (distance / audibleRadius))

        if distanceMix <= 0.01 {
            player.volume = 0
            return
        }

        player.pan = max(-1, min(1, dx / 18))
        player.volume = min(0.52, cue.defaultVolume * 0.46 * distanceMix)
    }

    private func parkedOwnedCarCue(for kind: DriveableVehicleKind) -> AudioCueID {
        switch kind {
        case .light:
            return .playerEngineLight
        case .sedan:
            return .playerEngineSedan
        case .sport:
            return .playerEngineSport
        case .coupe:
            return .playerEngineCoupe
        case .roadster:
            return .trafficEngineRoadster
        }
    }

    private func outdoorWorldPoint(for roomID: RoomID, position: GridPosition) -> OutdoorCarWorldPosition {
        switch roomID {
        case .street:
            let x = (Float(position.x) / 14.0) * 68.0 - 34.0
            let z = Float(7 - position.y) * 2.5
            return OutdoorCarWorldPosition(x: x, z: z)
        case .mainStreet:
            let x = (Float(position.x) / Float(max(1, MainStreetRoom.width - 1))) * 180.0 - 90.0
            let z = 23.5 + (Float((MainStreetRoom.height - 1) - position.y) / Float(max(1, MainStreetRoom.height - 1))) * 30.0
            return OutdoorCarWorldPosition(x: x, z: z)
        default:
            return OutdoorCarWorldPosition(x: 0, z: 0)
        }
    }

    private func manhattanDistance(from lhs: GridPosition, to rhs: GridPosition) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }
}
