import Foundation

extension GameViewModel {
    func handleKeyboardInput(_ input: KeyboardInputEvent) {
        switch input {
        case let .press(command):
            handleKeyPress(command)
        case let .release(command):
            handleKeyRelease(command)
        case let .command(command):
            if state.controlledCar != nil {
                switch command {
                case .moveForward, .moveBackward, .moveLeft, .moveRight:
                    return
                default:
                    break
                }
            }
            handle(command)
        }
    }

    func statePayload(recentPhrases: [String]) -> [String: Any] {
        let stageTitle: String
        switch stage {
        case .welcome:
            stageTitle = "welcome"
        case .characterCreation:
            stageTitle = "characterCreation"
        case .exploration:
            stageTitle = "exploration"
        case .finished:
            stageTitle = "finished"
        }

        return [
            "running": stage != .finished,
            "stage": stageTitle,
            "roomID": currentRoom.id.rawValue,
            "roomTitle": roomTitle,
            "focusTitle": focusTitle,
            "focusShortText": focusShortText,
            "statusText": statusText,
            "holdText": holdText,
            "inventoryOpen": isInventoryOpen,
            "inventoryTitle": inventoryTitle,
            "inventoryText": inventoryText,
            "character": currentCharacterSummary,
            "coins": state.player.coins,
            "position": [
                "x": debugRoomPosition.x,
                "y": debugRoomPosition.y
            ],
            "controlledCar": state.controlledCar.map { car in
                [
                    "id": car.id.uuidString,
                    "title": car.title,
                    "kind": car.kind.rawValue,
                    "speed": car.speed,
                    "phase": car.phase.rawValue,
                    "engineState": car.engineState.rawValue,
                    "worldX": car.worldPosition.x,
                    "worldZ": car.worldPosition.z
                ]
            } ?? NSNull(),
            "streetCars": audioCoordinator.streetDebugSnapshotPayload(),
            "recentEvents": Array(eventLog.prefix(12)),
            "recentPhrases": recentPhrases
        ]
    }

    func continueFromWelcome() {
        flowController.enter(.characterCreation)
        stage = flowController.currentStage
        let text = "Открыта форма создания персонажа. Выбери тип персонажа, введи имя и нажми завершить."
        announce(text)
    }

    func finishCharacterCreation() {
        let safeName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else {
            announce("Сначала введи имя персонажа.")
            return
        }

        characterName = safeName
        flowController.enter(.exploration)
        stage = flowController.currentStage

        let room = rooms[.hallway]!
        cancelKettleBoilingTask(resetWaterState: false)
        state = WorldRuntimeState(
            player: PlayerState(
                roomID: .hallway,
                roomPosition: room.spawnPosition,
                focusedTarget: .none,
                pose: .standing,
                heldItem: nil,
                hasCompletedTutorial: state.player.hasCompletedTutorial
            )
        )
        stopDrivingLoop()
        resetDrivingInput()
        carLifecycleTask?.cancel()
        carLifecycleTask = nil
        carLifecycleMachine.reset()
        driveElapsedTime = 0
        reverseHoldElapsed = 0
        gateAutoPassLockedZ = nil
        lastDrivingHintText = ""
        lastDrivingHintAt = .distantPast
        audioCoordinator.stopControlledCarAudio()
        bedAnchorPosition = nil
        doorLifecycleMachines.removeAll()
        cancelGateTransitionTasks(resetMachines: true)
        cancelNeighborTasks()
        neighborEncounterMachine.resetToCalm()
        neighborDoorHitsTarget = 0
        groceryStoreClerkMachine.reset()
        debugNeighborResponsePauseRange = nil
        debugNeighborBreakInPauseRange = nil
        debugNeighborDoorHitsTargetOverride = nil
        debugNeighborFootstepCountOverride = nil
        debugNeighborFootstepPauseOverride = nil

        refreshScreenState()
        addLog("Создан персонаж: \(selectedCharacterKind.rawValue), \(safeName)")
        let prompt = currentShortPrompt()
        let introText = prompt.isEmpty
            ? "Персонаж \(safeName) появился в квартире. \(room.entryAnnouncement)"
            : "Персонаж \(safeName) появился в квартире. \(room.entryAnnouncement) \(prompt)"
        announce(introText)
        maybeShowTutorial()
    }

    func handle(_ command: GameCommand) {
        guard stage == .exploration else { return }

        if state.controlledCar != nil || carLifecycleMachine.isBusyWithDoorOrEngine {
            switch command {
            case .moveForward, .moveBackward, .moveLeft, .moveRight:
                if state.controlledCar != nil {
                    if state.controlledCar?.engineState != .running {
                        announceDrivingHintIfNeeded("Мотор заглушен. Нажми E, чтобы завести машину.", minimumGap: 1.4)
                        return
                    }
                    applyDriveCommandImpulse(for: command)
                }
                return
            case .primaryAction:
                performPrimaryAction()
                return
            case .describeFocus:
                describeCurrentFocus()
                return
            default:
                return
            }
        }

        if command == .locationMenuToggle {
            toggleLocationMenu()
            return
        }

        if isLocationMenuOpen {
            handleLocationMenuCommand(command)
            return
        }

        if command == .inventoryToggle {
            toggleInventory()
            return
        }

        if inventoryMachine.isOpen {
            handleInventoryCommand(command)
            return
        }

        switch command {
        case .moveForward:
            guard canMoveNow() else { return }
            movePlayer(command)
        case .moveBackward:
            guard canMoveNow() else { return }
            movePlayer(command)
        case .moveLeft:
            guard canMoveNow() else { return }
            movePlayer(command)
        case .moveRight:
            guard canMoveNow() else { return }
            movePlayer(command)
        case .primaryAction:
            performPrimaryAction()
        case .forceAction:
            performAction(for: .force, missingText: "Сейчас здесь нечего ломать или бить.")
        case .throwObject:
            performAction(for: .throwItem, missingText: "Сейчас тут нечего сбрасывать или отталкивать.")
        case .describeFocus:
            describeCurrentFocus()
        case .placeHeldItem:
            performAction(for: .placeHeldItem, missingText: "Сейчас предмет некуда положить.")
        case .inventoryQuickAction:
            if let action = inventoryQuickAction() {
                apply(action)
            } else if state.player.heldItem != nil {
                announce("Сейчас предмет некуда быстро положить.")
            }
        case .locationMenuConfirm:
            confirmLocationMenuSelection()
        case .locationMenuToggle:
            break
        case .inventoryToggle:
            break
        }
    }

    func dismissTutorial() {
        isTutorialVisible = false
    }

    func resetForNewSession() {
        cancelNeighborTasks()
        cancelKettleBoilingTask(resetWaterState: false)
        carLifecycleTask?.cancel()
        carLifecycleTask = nil
        stopDrivingLoop()
        resetDrivingInput()
        state.controlledCar = nil
        state.parkedOwnedCars = [:]
        carLifecycleMachine.reset()
        driveElapsedTime = 0
        reverseHoldElapsed = 0
        gateAutoPassLockedZ = nil
        lastDrivingHintText = ""
        lastDrivingHintAt = .distantPast
        neighborDoorHitsTarget = 0
        groceryStoreClerkMachine.reset()
        debugNeighborResponsePauseRange = nil
        debugNeighborBreakInPauseRange = nil
        debugNeighborDoorHitsTargetOverride = nil
        debugNeighborFootstepCountOverride = nil
        debugNeighborFootstepPauseOverride = nil
        audioCoordinator.playAmbient(nil)
        audioCoordinator.setStreetPresence(.off, fadeDuration: 0)
        audioCoordinator.setTrafficEnabled(false)
        eventLog.removeAll()
        tutorialText = ""
        isTutorialVisible = false
        setInventoryOpen(false)
        inventoryTitle = ""
        inventoryText = ""
        doorLifecycleMachines.removeAll()
        cancelGateTransitionTasks(resetMachines: true)
        neighborEncounterMachine.resetToCalm()
        audioCoordinator.stopControlledCarAudio()
    }

    func availableDebugScenarios() -> [[String: String]] {
        [
            ["id": "hallway_neighbor_door", "name": "hallway_neighbor_door", "title": "Соседская дверь"],
            ["id": "hallway_coat_rack", "name": "hallway_coat_rack", "title": "Вешалка"],
            ["id": "bedroom_bed", "name": "bedroom_bed", "title": "Кровать"],
            ["id": "bedroom_pillow", "name": "bedroom_pillow", "title": "Подушка"],
            ["id": "living_room_tv", "name": "living_room_tv", "title": "Телевизор"],
            ["id": "living_room_table", "name": "living_room_table", "title": "Стол"],
            ["id": "kitchen_fridge", "name": "kitchen_fridge", "title": "Холодильник"],
            ["id": "bathroom_mirror", "name": "bathroom_mirror", "title": "Зеркало"],
            ["id": "bathroom_street_door", "name": "bathroom_street_door", "title": "Дверь на улицу"],
            ["id": "street_entry", "name": "street_entry", "title": "Выход во двор"],
            ["id": "street_gate", "name": "street_gate", "title": "Калитка во дворе"],
            ["id": "main_street_entry", "name": "main_street_entry", "title": "Большая улица"],
            ["id": "main_street_grocery_entry", "name": "main_street_grocery_entry", "title": "Вход в продуктовый"],
            ["id": "grocery_store_counter", "name": "grocery_store_counter", "title": "Прилавок продуктового"],
            ["id": "street_parked_car", "name": "street_parked_car", "title": "Припаркованная машина"],
            ["id": "street_approaching_car", "name": "street_approaching_car", "title": "Машина заезжает"],
            ["id": "street_departing_car", "name": "street_departing_car", "title": "Машина уезжает"],
            ["id": "main_street_car_entry_left", "name": "main_street_car_entry_left", "title": "Машина заезжает слева"],
            ["id": "main_street_car_entry_right", "name": "main_street_car_entry_right", "title": "Машина заезжает справа"],
            ["id": "main_street_car_exit", "name": "main_street_car_exit", "title": "Машина выезжает на улицу"]
        ]
    }

    @discardableResult
    func runDebugScenario(named name: String) -> Bool {
        resetNeighborEncounterState()

        switch name {
        case "hallway_neighbor_door":
            audioCoordinator.clearStreetDebugScenario()
            neighborEncounterMachine.markDoorbellRaised()
            debugMovePlayer(to: .hallway, position: GridPosition(x: 1, y: 1))
        case "hallway_coat_rack":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .hallway, position: GridPosition(x: 3, y: 1))
        case "bedroom_bed":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .bedroom, position: GridPosition(x: 3, y: 2))
        case "bedroom_pillow":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .bedroom, position: GridPosition(x: 4, y: 2))
        case "living_room_tv":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .livingRoom, position: GridPosition(x: 4, y: 1))
        case "living_room_table":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .livingRoom, position: GridPosition(x: 4, y: 2))
        case "kitchen_fridge":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .kitchen, position: GridPosition(x: 5, y: 2))
        case "bathroom_mirror":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .bathroom, position: GridPosition(x: 3, y: 1))
        case "bathroom_street_door":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .bathroom, position: GridPosition(x: 4, y: 1))
        case "street_entry":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .street, position: GridPosition(x: 7, y: 14))
        case "street_gate":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .street, position: GridPosition(x: 7, y: 0))
        case "main_street_entry":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .mainStreet, position: MainStreetRoom.gatePosition)
        case "main_street_grocery_entry":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .mainStreet, position: MainStreetRoom.groceryDoorPosition)
        case "grocery_store_counter":
            audioCoordinator.clearStreetDebugScenario()
            debugMovePlayer(to: .groceryStore, position: GridPosition(x: 7, y: 4))
        case "street_parked_car":
            debugMovePlayer(to: .street, position: GridPosition(x: 6, y: 6))
            return audioCoordinator.runStreetDebugScenario(name)
        case "street_approaching_car", "street_departing_car":
            debugMovePlayer(to: .street, position: GridPosition(x: 7, y: 14))
            return audioCoordinator.runStreetDebugScenario(name)
        case "main_street_car_entry_left":
            debugMovePlayer(to: .mainStreet, position: GridPosition(x: 18, y: min(MainStreetRoom.height - 1, 138)))
            return audioCoordinator.runStreetDebugScenario(name)
        case "main_street_car_entry_right":
            debugMovePlayer(to: .mainStreet, position: GridPosition(x: MainStreetRoom.width - 19, y: min(MainStreetRoom.height - 1, 138)))
            return audioCoordinator.runStreetDebugScenario(name)
        case "main_street_car_exit":
            debugMovePlayer(to: .mainStreet, position: GridPosition(x: MainStreetRoom.width - 28, y: min(MainStreetRoom.height - 1, 138)))
            return audioCoordinator.runStreetDebugScenario(name)
        default:
            return false
        }

        return true
    }

    @discardableResult
    func debugTeleport(roomID rawRoomID: String, x: Int, y: Int) -> Bool {
        guard let roomID = RoomID(rawValue: rawRoomID),
              let room = rooms[roomID] else {
            return false
        }

        let safeX = min(max(0, x), room.width - 1)
        let safeY = min(max(0, y), room.height - 1)
        audioCoordinator.clearStreetDebugScenario()
        debugMovePlayer(to: roomID, position: GridPosition(x: safeX, y: safeY))
        return true
    }

    func debugMovePlayer(to roomID: RoomID, position: GridPosition) {
        cancelGateTransitionTasks(resetMachines: true)
        state.player.roomID = roomID
        state.player.roomPosition = position
        state.player.focusedTarget = .none
        setPlayerPose(.standing)
        bedAnchorPosition = nil
        refreshScreenState()
        addLog("Отладка: \(roomID.rawValue) \(position.x),\(position.y)")
        announce("Отладка. \(roomTitle). \(currentShortPrompt().isEmpty ? roomEmptyDescription() : currentShortPrompt())")
    }
}
