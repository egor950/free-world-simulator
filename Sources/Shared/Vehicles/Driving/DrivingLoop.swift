import Foundation

extension GameViewModel {
    func startDrivingLoopIfNeeded() {
        guard drivingLoopTask == nil else { return }
        guard state.controlledCar != nil else { return }

        drivingLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastTimestamp = ProcessInfo.processInfo.systemUptime

            while !Task.isCancelled {
                guard self.state.controlledCar != nil else { break }

                let now = ProcessInfo.processInfo.systemUptime
                let deltaTime = min(0.08, max(1.0 / 90.0, now - lastTimestamp))
                lastTimestamp = now
                self.driveElapsedTime += deltaTime
                self.updateControlledCar(deltaTime: deltaTime)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    func stopDrivingLoop() {
        drivingLoopTask?.cancel()
        drivingLoopTask = nil
        lastDrivingUIRefreshAt = 0
        lastDrivingWorldAudioSyncAt = 0
        lastDrivingRoomID = nil
        lastDrivingRoomPosition = nil
    }

    func updateControlledCar(deltaTime: TimeInterval) {
        guard var car = state.controlledCar else { return }
        let previousCar = car
        let blueprint = DriveableVehicleBlueprint.blueprint(for: car.kind)
        let engineRunning = car.engineState == .running
        let reverseMaxSpeed = min(14.0, blueprint.maxSpeed * 0.28)
        let reverseAcceleration = blueprint.acceleration * 0.65
        let speedBefore = car.speed
        let positionBefore = car.worldPosition
        let gateIsOpen = currentGateIsOpen()
        let isApproachingGate = car.worldPosition.z >= 9.0 && car.worldPosition.z <= 18.4
        let isOnCourtyardGateLine = abs(car.worldPosition.x) <= 10 && car.worldPosition.z >= 12.5 && car.worldPosition.z <= 18.2
        let isInsideGateAutoPassZone = gateIsOpen && shouldAutoPassGate(for: car)
        let useDirectGatePass = gateIsOpen &&
            engineRunning &&
            isGasPressed &&
            car.worldPosition.z >= 16.8 &&
            car.worldPosition.z <= 23.3 &&
            abs(car.worldPosition.x) <= 12.5

        if !engineRunning {
            reverseHoldElapsed = 0
            let sign = car.speed == 0 ? 0.0 : (car.speed > 0 ? 1.0 : -1.0)
            car.speed -= sign * min(5.0, abs(car.speed) * 2.4 + 1.5) * deltaTime
            if abs(car.speed) < 0.08 {
                car.speed = 0
            }
        } else if isGasPressed && !isBrakePressed {
            reverseHoldElapsed = 0
            let gasAccel = blueprint.acceleration
            let rollingDecel = 1.3
            let dragDecel = 0.012 * max(0, car.speed)
            car.speed += (gasAccel - rollingDecel - dragDecel) * deltaTime
        } else if isBrakePressed {
            if car.speed > 0.35 {
                reverseHoldElapsed = 0
                let rollingDecel = 1.3
                let dragDecel = 0.012 * abs(car.speed)
                car.speed += (-18.0 - rollingDecel - dragDecel) * deltaTime
            } else {
                reverseHoldElapsed += deltaTime
                if reverseHoldElapsed >= 0.34 {
                    let rollingDecel = 1.3
                    let dragDecel = 0.012 * abs(car.speed)
                    car.speed += (-reverseAcceleration + rollingDecel + dragDecel) * deltaTime
                } else if car.speed > 0 {
                    car.speed = max(0, car.speed - 4.5 * deltaTime)
                } else {
                    car.speed = 0
                }
            }
        } else {
            reverseHoldElapsed = 0
            if abs(car.speed) < 0.7 {
                let sign = car.speed == 0 ? 0.0 : (car.speed > 0 ? 1.0 : -1.0)
                car.speed -= sign * 3.0 * deltaTime
            } else {
                let sign = car.speed > 0 ? 1.0 : -1.0
                let rollingDecel = 1.3
                let dragDecel = 0.012 * abs(car.speed)
                car.speed -= sign * (rollingDecel + dragDecel) * deltaTime
            }
        }

        if !isGasPressed && car.speed > 0, car.speed < 0.7 {
            car.speed = max(0, car.speed - 3.0 * deltaTime)
        }
        if !isBrakePressed && car.speed < 0, abs(car.speed) < 0.7 {
            car.speed = min(0, car.speed + 3.0 * deltaTime)
        }

        if !gateIsOpen && isOnCourtyardGateLine && car.speed > 0 {
            let distanceToGate = max(0, Double(17.45 - car.worldPosition.z))
            let stopAssistSpeed = max(0.35, min(4.8, distanceToGate * 1.9))
            car.speed = min(car.speed, stopAssistSpeed)
        }

        car.speed = min(max(-reverseMaxSpeed, car.speed), blueprint.maxSpeed)

        var steerAxis = 0.0
        if engineRunning && !isInsideGateAutoPassZone {
            if isLeftPressed { steerAxis -= 1 }
            if isRightPressed { steerAxis += 1 }
        }
        steerAxis = max(-1, min(1, steerAxis))
        car.steeringAxis = steerAxis

        let speedNorm = blueprint.maxSpeed > 0 ? min(1.0, max(0.0, abs(car.speed) / blueprint.maxSpeed)) : 0
        let steeringPower = computeSteeringPower(
            base: blueprint.steeringBase,
            speedFactor: blueprint.steeringSpeedFactor,
            speedNorm: speedNorm,
            isBraking: isBrakePressed
        )

        if useDirectGatePass {
            car.speed = max(car.speed, 1.9)
            let centeredX = moveToward(
                current: Double(car.worldPosition.x),
                target: 0,
                maxDelta: 26.0 * deltaTime
            )
            car.worldPosition.x = Float(centeredX)
            car.worldPosition.z += Float(car.speed * deltaTime)
            if car.worldPosition.z >= 19.8 {
                car.worldPosition.z = max(car.worldPosition.z, 23.7)
            }
        } else {
            let lateralBase = 4.1 + min(9.4, abs(car.speed) * 0.28)
            let speedSteeringMix = min(1.0, abs(car.speed) / 4.0)
            let crawlSteeringMix = (isGasPressed || isBrakePressed) ? 0.34 : 0.0
            let lateralGrip = max(crawlSteeringMix, speedSteeringMix)
            let lateralDelta = Double(steerAxis) * steeringPower * lateralBase * lateralGrip * deltaTime

            car.worldPosition.z += Float(car.speed * deltaTime)
            car.worldPosition.x += Float(lateralDelta)
        }

        if car.roomID == .mainStreet {
            let storeZ: Float = 30.25
            let isNearStoreBand = car.worldPosition.z >= storeZ - 2.0 && car.worldPosition.z <= storeZ + 4.8
            let steeringAssistDelta = (10.8 + abs(car.speed) * 0.7) * deltaTime

            if isNearStoreBand && car.speed > 0.18 {
                if isRightPressed {
                    let parkingTargetX = 68.0
                    let assistedX = moveToward(
                        current: Double(car.worldPosition.x),
                        target: parkingTargetX,
                        maxDelta: steeringAssistDelta
                    )
                    car.worldPosition.x = Float(max(Double(car.worldPosition.x), assistedX))
                } else if isLeftPressed {
                    let centerTargetX = 0.0
                    let assistedX = moveToward(
                        current: Double(car.worldPosition.x),
                        target: centerTargetX,
                        maxDelta: steeringAssistDelta
                    )
                    car.worldPosition.x = Float(assistedX)
                }
            }
        }

        if isInsideGateAutoPassZone || useDirectGatePass {
            let centeredX = moveToward(
                current: Double(car.worldPosition.x),
                target: 0,
                maxDelta: 24.0 * deltaTime
            )
            car.worldPosition.x = Float(centeredX)
            if abs(car.worldPosition.x) < 0.65 {
                car.worldPosition.x = 0
            }
        } else if isApproachingGate && !isLeftPressed && !isRightPressed {
            let centerPull = gateIsOpen ? 4.6 : 5.8
            let centeredX = moveToward(
                current: Double(car.worldPosition.x),
                target: 0,
                maxDelta: centerPull * deltaTime
            )
            car.worldPosition.x = Float(centeredX)
        } else if car.roomID == .street && !isLeftPressed && !isRightPressed {
            let settledX = moveToward(
                current: Double(car.worldPosition.x),
                target: 0,
                maxDelta: 0.8 * deltaTime
            )
            car.worldPosition.x = Float(settledX)
        }

        car.headingRadians = 0

        constrainControlledCar(&car, gateIsOpen: gateIsOpen)

        let isInOpenGatePassage = gateIsOpen &&
            engineRunning &&
            isGasPressed &&
            positionBefore.z >= 16.8 &&
            positionBefore.z <= 23.3
        if isInOpenGatePassage {
            let lockedZ = max(gateAutoPassLockedZ ?? positionBefore.z, positionBefore.z)
            let minForwardStep = Float(0.35 * deltaTime)
            let nextLockedZ = lockedZ + minForwardStep
            gateAutoPassLockedZ = nextLockedZ
            car.worldPosition.z = max(car.worldPosition.z, nextLockedZ)
        } else if car.worldPosition.z >= 23.55 || !gateIsOpen || !isGasPressed {
            gateAutoPassLockedZ = nil
        }

        let movedDistance = hypot(
            Double(car.worldPosition.x - positionBefore.x),
            Double(car.worldPosition.z - positionBefore.z)
        )
        let intendedDistance = abs(car.speed) * deltaTime
        let movementWasBlocked = intendedDistance > 0.12 && movedDistance < intendedDistance * 0.18
        if movementWasBlocked {
            if car.speed > 0 {
                car.speed = max(0, min(car.speed, speedBefore - 18.0 * deltaTime))
            } else if car.speed < 0 {
                car.speed = min(0, max(car.speed, speedBefore + 18.0 * deltaTime))
            }
        }

        car.roomID = resolvedOutdoorRoomID(for: car.worldPosition, previousRoomID: car.roomID)
        let roomPosition = gridPosition(for: car.worldPosition, roomID: car.roomID)
        state.player.roomID = car.roomID
        state.player.roomPosition = roomPosition
        state.player.focusedTarget = .none

        if abs(car.speed) > 0.4 {
            _ = carLifecycleMachine.startDriving()
            car.phase = .driving
        } else {
            _ = carLifecycleMachine.park()
            if car.engineState != .starting {
                car.phase = .parked
            }
        }

        state.controlledCar = car
        let lanePan = controlledCarLanePan(car)
        audioCoordinator.updateControlledCarAudio(
            speed: car.speed,
            maxSpeed: blueprint.maxSpeed,
            gasPressed: isGasPressed,
            brakePressed: isBrakePressed,
            elapsedTime: driveElapsedTime,
            lanePan: lanePan
        )
        refreshDrivingPresentationIfNeeded(
            currentCar: car,
            previousCar: previousCar,
            roomPosition: roomPosition
        )
        updateDrivingHint(currentCar: car, previousSpeed: speedBefore)
    }

    func refreshDrivingPresentationIfNeeded(
        currentCar: ControlledCarState,
        previousCar: ControlledCarState,
        roomPosition: GridPosition
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let roomChanged = previousCar.roomID != currentCar.roomID
        let phaseChanged = previousCar.phase != currentCar.phase || previousCar.engineState != currentCar.engineState
        let speedBucketChanged = displayedSpeedKilometersPerHour(for: previousCar.speed) != displayedSpeedKilometersPerHour(for: currentCar.speed)
        let steeringChanged = abs(previousCar.steeringAxis - currentCar.steeringAxis) >= 0.45
        let shouldRefreshUI = roomChanged ||
            phaseChanged ||
            speedBucketChanged ||
            steeringChanged ||
            now - lastDrivingUIRefreshAt >= 0.12

        if shouldRefreshUI {
            refreshScreenState(syncAudio: false)
            lastDrivingUIRefreshAt = now
        }

        let roomPositionChanged = lastDrivingRoomID != currentCar.roomID || lastDrivingRoomPosition != roomPosition
        let shouldSyncWorldAudio = roomChanged ||
            roomPositionChanged ||
            now - lastDrivingWorldAudioSyncAt >= 0.22

        if shouldSyncWorldAudio {
            syncAudioWorldState()
            lastDrivingWorldAudioSyncAt = now
            lastDrivingRoomID = currentCar.roomID
            lastDrivingRoomPosition = roomPosition
        }
    }
}
