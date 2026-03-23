import Foundation

extension GameViewModel {
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
            "position": [
                "x": debugRoomPosition.x,
                "y": debugRoomPosition.y
            ],
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
        bedAnchorPosition = nil
        doorLifecycleMachines.removeAll()
        cancelNeighborTasks()
        neighborEncounterMachine.resetToCalm()
        neighborDoorHitsTarget = 0

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
        case .inventoryToggle, .inventoryQuickAction:
            break
        }
    }

    func dismissTutorial() {
        isTutorialVisible = false
    }

    func resetForNewSession() {
        cancelNeighborTasks()
        neighborDoorHitsTarget = 0
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
        neighborEncounterMachine.resetToCalm()
    }

    func availableDebugScenarios() -> [[String: String]] {
        [
            ["id": "hallway_neighbor_door", "title": "Соседская дверь"],
            ["id": "hallway_coat_rack", "title": "Вешалка"],
            ["id": "bedroom_bed", "title": "Кровать"],
            ["id": "bedroom_pillow", "title": "Подушка"],
            ["id": "living_room_tv", "title": "Телевизор"],
            ["id": "living_room_table", "title": "Стол"],
            ["id": "kitchen_fridge", "title": "Холодильник"],
            ["id": "bathroom_mirror", "title": "Зеркало"],
            ["id": "bathroom_street_door", "title": "Дверь на улицу"],
            ["id": "street_entry", "title": "Выход во двор"],
            ["id": "street_parked_car", "title": "Припаркованная машина"],
            ["id": "street_approaching_car", "title": "Машина заезжает"],
            ["id": "street_departing_car", "title": "Машина уезжает"]
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
        case "street_parked_car", "street_approaching_car", "street_departing_car":
            debugMovePlayer(to: .street, position: GridPosition(x: 7, y: 14))
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
