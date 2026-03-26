import Foundation

extension GameViewModel {
    func handleKeyPress(_ command: GameCommand) {
        switch command {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            if state.controlledCar != nil {
                setDrivingInput(command, isPressed: true)
            } else {
                handle(command)
            }
        default:
            handle(command)
        }
    }

    func handleKeyRelease(_ command: GameCommand) {
        guard state.controlledCar != nil else { return }

        switch command {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            setDrivingInput(command, isPressed: false)
        default:
            break
        }
    }

    func resetDrivingInput() {
        isGasPressed = false
        isBrakePressed = false
        isLeftPressed = false
        isRightPressed = false
        reverseHoldElapsed = 0
        gateAutoPassLockedZ = nil
        for task in pendingDriveCommandResetTasks.values {
            task.cancel()
        }
        pendingDriveCommandResetTasks.removeAll()
    }

    func setDrivingInput(_ command: GameCommand, isPressed: Bool) {
        if isPressed {
            pendingDriveCommandResetTasks[command]?.cancel()
            pendingDriveCommandResetTasks[command] = nil
        }

        switch command {
        case .moveForward:
            isGasPressed = isPressed
        case .moveBackward:
            isBrakePressed = isPressed
        case .moveLeft:
            isLeftPressed = isPressed
        case .moveRight:
            isRightPressed = isPressed
        default:
            break
        }
    }

    func applyDriveCommandImpulse(for command: GameCommand) {
        setDrivingInput(command, isPressed: true)
        pendingDriveCommandResetTasks[command]?.cancel()
        pendingDriveCommandResetTasks[command] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self else { return }
            self.setDrivingInput(command, isPressed: false)
            self.pendingDriveCommandResetTasks[command] = nil
        }
    }

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
    }

    func updateControlledCar(deltaTime: TimeInterval) {
        guard var car = state.controlledCar else { return }
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
            car.worldPosition.z >= 17.2 &&
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
            car.speed = max(car.speed, 4.6)
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
            let isNearStoreBand = car.worldPosition.z >= storeZ - 2.5 && car.worldPosition.z <= storeZ + 6.5
            let steeringAssistDelta = (8.8 + abs(car.speed) * 0.55) * deltaTime

            if isNearStoreBand && car.speed > 0.18 {
                if isRightPressed {
                    let parkingTargetX = 74.0
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
            car.speed > 0.2 &&
            positionBefore.z >= 17.3 &&
            positionBefore.z <= 23.3
        if isInOpenGatePassage {
            let lockedZ = max(gateAutoPassLockedZ ?? positionBefore.z, positionBefore.z)
            let minForwardStep = Float(0.55 * deltaTime)
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

        car.roomID = worldRoomID(for: car.worldPosition)
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
        refreshScreenState()
        updateDrivingHint(currentCar: car, previousSpeed: speedBefore)
    }

    func computeSteeringPower(
        base: Double,
        speedFactor: Double,
        speedNorm: Double,
        isBraking: Bool
    ) -> Double {
        let steerBase = max(0.45, min(1.28, base / 210.0))
        let topFactor = max(0.05, min(1.0, speedFactor / 100.0))
        let highSpeed = 1.0 - speedNorm * (1.0 - topFactor)
        let brakingPenalty = isBraking ? 0.62 : 1.0
        return steerBase * highSpeed * brakingPenalty
    }

    func currentGateIsOpen() -> Bool {
        let gateDoor = rooms[.street]?.doors[StreetRoom.gateDoorID]
        return gateDoor.map { timedDoorConfiguration(for: $0) != nil ? gateMachine(for: $0).isOpen : isDoorOpened($0) } ?? false
    }

    func constrainControlledCar(_ car: inout ControlledCarState, gateIsOpen: Bool) {
        let previousX = car.worldPosition.x
        let previousZ = car.worldPosition.z
        let isGatePassageZone = car.worldPosition.z > 17.45 && car.worldPosition.z < 23.5

        if gateIsOpen && isGatePassageZone && abs(car.worldPosition.x) <= 13.5 {
            car.worldPosition.x = min(10, max(-10, car.worldPosition.x))
            car.worldPosition.z = min(23.5, max(-17.5, car.worldPosition.z))
        } else if car.worldPosition.z >= 23.5 {
            car.worldPosition.x = min(90, max(-90, car.worldPosition.x))
            car.worldPosition.z = min(53.5, max(23.5, car.worldPosition.z))
        } else {
            car.worldPosition.x = min(34, max(-34, car.worldPosition.x))
            car.worldPosition.z = min(17.5, max(-17.5, car.worldPosition.z))
        }

        if isGatePassageZone {
            if gateIsOpen {
                if abs(car.worldPosition.x) <= 13.5 {
                    car.worldPosition.x = min(10, max(-10, car.worldPosition.x))
                } else {
                    car.worldPosition.z = 17.45
                    if car.speed > 0 {
                        car.speed = 0
                    }
                }
            } else {
                car.worldPosition.z = 17.45
                if car.speed > 0 {
                    car.speed = 0
                }
            }
        }

        if car.worldPosition.x != previousX || car.worldPosition.z != previousZ {
            if car.worldPosition.x == -34 || (car.roomID == .street && car.worldPosition.x == 34) {
                car.speed = min(0, car.speed)
            }
            if car.worldPosition.z == -17.5 || car.worldPosition.z == 53.5 {
                car.speed = min(0, car.speed)
            }
        }
    }

    func updateDrivingHint(currentCar: ControlledCarState, previousSpeed: Double) {
        let cameToStop = abs(currentCar.speed) <= 0.05 && abs(previousSpeed) > 0.55

        if currentCar.engineState != .running {
            if currentCar.phase == .parked {
                announceDrivingHintIfNeeded("Мотор заглушен. Нажми E, чтобы завести машину.", minimumGap: 2.2)
            }
            return
        }

        if currentCar.roomID == .street, currentCar.worldPosition.z > 15.6 {
            let gateIsOpen = currentGateIsOpen()
            if !gateIsOpen && cameToStop {
                announceDrivingHintIfNeeded("Перед тобой калитка. Остановись, выйди и открой её пешком.")
                return
            }
            if gateIsOpen && shouldAutoPassGate(for: currentCar) {
                announceDrivingHintIfNeeded("Калитка открыта. Просто держись прямо, машина сама пройдёт через проём.", minimumGap: 1.4)
                return
            }
            if gateIsOpen && currentCar.worldPosition.z >= 16.5 && abs(currentCar.worldPosition.x) > 10.5 && cameToStop {
                announceDrivingHintIfNeeded("Калитка уже открыта, но машина смещена. Вернись ближе к центру проезда.", minimumGap: 1.3)
                return
            }
            if gateIsOpen && currentCar.worldPosition.z >= 18.0 && currentCar.worldPosition.z < 23.5 {
                announceDrivingHintIfNeeded("Калитка открыта. Теперь держись прямо и выезжай на большую улицу.", minimumGap: 1.6)
                return
            }
        }

        if currentCar.roomID == .street,
           currentCar.worldPosition.z >= 9.0,
           currentCar.worldPosition.z < 15.6,
           currentCar.speed > 0.6 {
            announceDrivingHintIfNeeded("Калитка уже впереди. Просто держись прямо.", minimumGap: 1.8)
            return
        }

        if currentCar.roomID == .street, cameToStop {
            if currentCar.worldPosition.x <= -33.9 {
                announceDrivingHintIfNeeded("Слева стена дома. Дальше машина не пройдёт.")
                return
            }
            if currentCar.worldPosition.x >= 33.9 {
                announceDrivingHintIfNeeded("Справа край двора. Дальше машина не пройдёт.")
                return
            }
            if currentCar.worldPosition.z <= -17.4 {
                announceDrivingHintIfNeeded("Позади край двора. Дальше машины не проходит.")
                return
            }
        }

        if currentCar.roomID == .mainStreet {
            let storeZ: Float = 30.25
            if currentCar.worldPosition.z < storeZ - 5.5 {
                announceDrivingHintIfNeeded("Едь прямо по большой улице и держись по центру. До продуктового ещё есть путь.", minimumGap: 2.3)
                return
            }

            if currentCar.worldPosition.z <= storeZ + 7 {
                if currentCar.worldPosition.x < 10 {
                    announceDrivingHintIfNeeded("Ты поравнялся с магазином. Теперь начинай плавно уходить вправо.", minimumGap: 1.9)
                    return
                }
                if currentCar.worldPosition.x < 30 {
                    announceDrivingHintIfNeeded("Поворот правильный. Продолжай плавно держаться правее.", minimumGap: 1.8)
                    return
                }
                if currentCar.worldPosition.x < 54 {
                    announceDrivingHintIfNeeded("Хорошо. Ещё немного правее к парковке продуктового.", minimumGap: 1.6)
                    return
                }
                if currentCar.worldPosition.x <= 78 {
                    announceDrivingHintIfNeeded("Ты у парковки продуктового. Сбавляй ход и готовься остановиться.", minimumGap: 1.8)
                    return
                }
            }

            if cameToStop {
                if currentCar.worldPosition.x <= -89.9 {
                    announceDrivingHintIfNeeded("Слева край большой улицы. Дальше машина не пройдёт.")
                    return
                }
                if currentCar.worldPosition.x >= 89.9 {
                    announceDrivingHintIfNeeded("Справа край большой улицы. Дальше машина не пройдёт.")
                    return
                }
                if currentCar.worldPosition.z <= 23.55 {
                    announceDrivingHintIfNeeded("Позади снова двор и калитка. Дальше назад машина не прошла.")
                    return
                }
                if currentCar.worldPosition.z >= 53.45 {
                    announceDrivingHintIfNeeded("Впереди край большой улицы. Дальше пока не проехать.")
                    return
                }
            }
        }
    }

    func moveToward(current: Double, target: Double, maxDelta: Double) -> Double {
        if current < target {
            return min(target, current + maxDelta)
        }
        return max(target, current - maxDelta)
    }

    func controlledCarLanePan(_ car: ControlledCarState) -> Float {
        let targetX = preferredDriveLineX(for: car)
        let span = preferredDriveLineSpan(for: car)
        let offset = Double(car.worldPosition.x) - targetX
        let normalized = max(-1.0, min(1.0, offset / span))
        return Float(normalized)
    }

    func preferredDriveLineX(for car: ControlledCarState) -> Double {
        _ = car
        return 0
    }

    func preferredDriveLineSpan(for car: ControlledCarState) -> Double {
        switch car.roomID {
        case .street:
            return 10
        case .mainStreet:
            return 24
        default:
            return 12
        }
    }

    func shouldAutoPassGate(for car: ControlledCarState) -> Bool {
        guard car.speed > 0.18 else { return false }

        if car.roomID == .street {
            return car.worldPosition.z >= 15.8 &&
                car.worldPosition.z <= 23.2 &&
                abs(car.worldPosition.x) <= 12.5
        }

        if car.roomID == .mainStreet {
            return car.worldPosition.z >= 23.2 &&
                car.worldPosition.z <= 26.8 &&
                abs(car.worldPosition.x) <= 12.5
        }

        return false
    }
}
