import Foundation

extension GameViewModel {
    func performControlledCarPrimaryAction() {
        guard let controlledCar = state.controlledCar else { return }

        if controlledCar.engineState != .running {
            startControlledCarEngine()
            return
        }

        attemptExitControlledCar()
    }

    func attemptEnterDriveableCar(_ context: DriveableCarContext) {
        guard !carLifecycleMachine.isBusyWithDoorOrEngine else {
            announce("Сейчас подожди, дверь или мотор ещё заняты.")
            return
        }

        guard context.kind != .roadster else {
            announce("В родстер пока нельзя сесть.")
            return
        }

        let blueprint = DriveableVehicleBlueprint.blueprint(for: context.kind)
        let controlledCar: ControlledCarState
        let skipStartup: Bool

        if context.isOwned {
            guard let ownedCar = state.parkedOwnedCars[context.id] else {
                announce("Эта машина уже недоступна.")
                return
            }
            state.removeParkedOwnedCar(id: ownedCar.id)
            controlledCar = ControlledCarState(
                id: ownedCar.id,
                kind: ownedCar.kind,
                title: ownedCar.title,
                roomID: ownedCar.roomID,
                worldPosition: ownedCar.worldPosition,
                headingRadians: ownedCar.headingRadians,
                speed: 0,
                steeringAxis: 0,
                directionLeftToRight: ownedCar.directionLeftToRight,
                engineState: ownedCar.isEngineRunning ? .running : .off,
                phase: .carDoorOpeningForEnter
            )
            skipStartup = ownedCar.isEngineRunning
        } else {
            guard let snapshot = audioCoordinator.claimParkedCar(id: context.id) else {
                announce("Эта машина уже уехала или больше недоступна.")
                return
            }
            let roomID = worldRoomID(for: snapshot.worldPosition)
            controlledCar = ControlledCarState(
                id: snapshot.id,
                kind: snapshot.vehicleKind,
                title: snapshot.title,
                roomID: roomID,
                worldPosition: snapshot.worldPosition,
                headingRadians: initialHeadingRadians(
                    for: snapshot.worldPosition,
                    roomID: roomID,
                    directionLeftToRight: snapshot.directionLeftToRight
                ),
                speed: 0,
                steeringAxis: 0,
                directionLeftToRight: snapshot.directionLeftToRight,
                engineState: .off,
                phase: .carDoorOpeningForEnter
            )
            skipStartup = false
        }

        state.controlledCar = controlledCar
        state.player.focusedTarget = .none
        driveElapsedTime = 0
        resetDrivingInput()
        _ = carLifecycleMachine.beginEnterOpening()
        refreshScreenState()
        addLog("Садишься в машину: \(controlledCar.title)")
        audioCoordinator.playPlayerCarDoorOpen()

        carLifecycleTask?.cancel()
        carLifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: UInt64(self.audioCoordinator.playerCarDoorOpenDuration() * 1_000_000_000))
            guard !Task.isCancelled, self.state.controlledCar?.id == controlledCar.id else { return }

            _ = self.carLifecycleMachine.beginEntering()
            self.state.controlledCar?.phase = .enteringVehicle
            self.refreshScreenState()

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, self.state.controlledCar?.id == controlledCar.id else { return }

            _ = self.carLifecycleMachine.beginEnterClosing()
            self.state.controlledCar?.phase = .carDoorClosingAfterEnter
            self.audioCoordinator.playPlayerCarDoorClose()
            self.refreshScreenState()

            try? await Task.sleep(nanoseconds: UInt64(self.audioCoordinator.playerCarDoorCloseDuration() * 1_000_000_000))
            guard !Task.isCancelled, self.state.controlledCar?.id == controlledCar.id else { return }

            if skipStartup {
                self.audioCoordinator.activateControlledCarAudio(for: blueprint)
                self.state.controlledCar?.engineState = .running
                self.state.controlledCar?.phase = .engineIdle
                _ = self.carLifecycleMachine.finishEnterToIdle()
                self.refreshScreenState()
                self.announce("Ты сел в \(controlledCar.title). Мотор уже работал, можно ехать.")
                self.startDrivingLoopIfNeeded()
                return
            }

            self.state.controlledCar?.engineState = .off
            self.state.controlledCar?.phase = .parked
            _ = self.carLifecycleMachine.finishEnterToIdle()
            self.refreshScreenState()
            self.announce("Ты сел в \(controlledCar.title). Мотор пока заглушен. Нажми E, чтобы завести.")
        }
    }

    func startControlledCarEngine() {
        guard let controlledCar = state.controlledCar else { return }
        guard !carLifecycleMachine.isBusyWithDoorOrEngine else {
            announce("Сейчас подожди, идёт дверь или заводка.")
            return
        }
        guard controlledCar.engineState != .running else {
            announce("Мотор уже работает.")
            return
        }

        let blueprint = DriveableVehicleBlueprint.blueprint(for: controlledCar.kind)
        audioCoordinator.activateControlledCarAudio(for: blueprint)
        _ = carLifecycleMachine.beginEngineStarting()
        state.controlledCar?.engineState = .starting
        state.controlledCar?.phase = .engineStarting
        refreshScreenState()

        let startupDuration = audioCoordinator.playControlledCarStartup(blueprint.startupCue)
        carLifecycleTask?.cancel()
        carLifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(startupDuration * 1_000_000_000))
            guard !Task.isCancelled, self.state.controlledCar?.id == controlledCar.id else { return }

            self.state.controlledCar?.engineState = .running
            self.state.controlledCar?.phase = .engineIdle
            _ = self.carLifecycleMachine.finishEnterToIdle()
            self.refreshScreenState()
            self.announce("Ты завёл мотор. Можно ехать.")
            self.startDrivingLoopIfNeeded()
        }
    }

    func attemptExitControlledCar() {
        guard let controlledCar = state.controlledCar else {
            return
        }

        guard !carLifecycleMachine.isBusyWithDoorOrEngine else {
            announce("Сейчас подожди, идёт дверь или заводка.")
            return
        }

        guard abs(controlledCar.speed) <= 0.35 else {
            announce("Сначала полностью останови машину.")
            return
        }

        resetDrivingInput()
        stopDrivingLoop()
        _ = carLifecycleMachine.beginExitOpening()
        state.controlledCar?.phase = .carDoorOpeningForExit
        refreshScreenState()
        audioCoordinator.playPlayerCarDoorOpen()

        carLifecycleTask?.cancel()
        carLifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: UInt64(self.audioCoordinator.playerCarDoorOpenDuration() * 1_000_000_000))
            guard !Task.isCancelled, self.state.controlledCar?.id == controlledCar.id else { return }

            _ = self.carLifecycleMachine.beginExiting()
            self.state.controlledCar?.phase = .exitingVehicle
            self.refreshScreenState()

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let car = self.state.controlledCar, car.id == controlledCar.id else { return }

            let parkedRoomID = self.worldRoomID(for: car.worldPosition)
            let parkedGridPosition = self.gridPosition(for: car.worldPosition, roomID: parkedRoomID)
            let exitPosition = self.nearestExitPosition(for: parkedGridPosition, roomID: parkedRoomID)

            self.state.player.roomID = parkedRoomID
            self.state.player.roomPosition = exitPosition
            self.state.player.focusedTarget = .none

            _ = self.carLifecycleMachine.beginExitClosing()
            self.state.controlledCar?.phase = .carDoorClosingAfterExit
            self.audioCoordinator.playPlayerCarDoorClose()
            self.refreshScreenState()

            try? await Task.sleep(nanoseconds: UInt64(self.audioCoordinator.playerCarDoorCloseDuration() * 1_000_000_000))
            guard !Task.isCancelled, let finalCar = self.state.controlledCar, finalCar.id == controlledCar.id else { return }

            let ownedCar = ParkedOwnedCarState(
                id: finalCar.id,
                kind: finalCar.kind,
                title: finalCar.title,
                roomID: parkedRoomID,
                worldPosition: finalCar.worldPosition,
                gridPosition: parkedGridPosition,
                headingRadians: finalCar.headingRadians,
                directionLeftToRight: finalCar.directionLeftToRight,
                isEngineRunning: finalCar.engineState == .running
            )
            self.state.setParkedOwnedCar(ownedCar)
            self.state.controlledCar = nil
            self.audioCoordinator.stopControlledCarAudio()
            _ = self.carLifecycleMachine.finishExit()
            self.refreshScreenState()

            if ownedCar.isEngineRunning {
                self.announce("Ты вышел из машины. Мотор оставлен заведённым.")
            } else {
                self.announce("Ты вышел из машины.")
            }
        }
    }

    func nearestExitPosition(for carPosition: GridPosition, roomID: RoomID) -> GridPosition {
        let candidates: [GridPosition]
        if roomID == .street && carPosition.y == 0 {
            candidates = [
                GridPosition(x: carPosition.x, y: carPosition.y + 1),
                GridPosition(x: carPosition.x - 1, y: carPosition.y),
                GridPosition(x: carPosition.x + 1, y: carPosition.y),
                GridPosition(x: carPosition.x, y: carPosition.y - 1)
            ]
        } else if roomID == .mainStreet && carPosition.x >= MainStreetRoom.width - 10 {
            candidates = [
                GridPosition(x: carPosition.x + 1, y: carPosition.y),
                GridPosition(x: carPosition.x, y: carPosition.y - 1),
                GridPosition(x: carPosition.x, y: carPosition.y + 1),
                GridPosition(x: carPosition.x - 1, y: carPosition.y)
            ]
        } else {
            candidates = [
                GridPosition(x: carPosition.x - 1, y: carPosition.y),
                GridPosition(x: carPosition.x, y: carPosition.y + 1),
                GridPosition(x: carPosition.x, y: carPosition.y - 1),
                GridPosition(x: carPosition.x + 1, y: carPosition.y)
            ]
        }

        let room = rooms[roomID] ?? currentRoom
        for candidate in candidates where candidate.x >= 0 && candidate.y >= 0 && candidate.x < room.width && candidate.y < room.height {
            return candidate
        }

        return carPosition
    }
}
