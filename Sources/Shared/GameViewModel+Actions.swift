import Foundation

extension GameViewModel {
    func performPrimaryAction() {
        if state.controlledCar != nil {
            performControlledCarPrimaryAction()
            return
        }

        if let driveableCar = currentFocusDriveableCarContext() {
            attemptEnterDriveableCar(driveableCar)
            return
        }

        if let door = currentFocusDoor,
           timedDoorConfiguration(for: door) != nil,
           isDoorOpened(door),
           let nearbyCar = nearestDriveableCarContext(maxDistance: 1) {
            attemptEnterDriveableCar(nearbyCar)
            return
        }

        if let door = currentFocusDoor {
            handleDoorAction(door)
            return
        }

        performAction(for: .primary, missingText: "Сейчас здесь нет основного действия.")
    }

    func performAction(for trigger: ActionTrigger, missingText: String) {
        guard let action = action(for: trigger) else {
            announce(missingText)
            return
        }

        apply(action)
    }

    func handleDoorAction(_ door: DoorDefinition) {
        if door.id == HallwayRoom.neighborDoorID {
            neighbor.handleNeighborDoor()
            return
        }

        if let configuration = timedDoorConfiguration(for: door) {
            handleTimedDoorAction(door, configuration: configuration)
            return
        }

        let machine = doorMachine(for: door)

        guard !machine.isLocked else {
            addLog("Дверь заперта: \(door.name)")
            announce(door.lockedText)
            return
        }

        if machine.isOpen {
            _ = machine.close()
            audioCoordinator.playEffect(door.closeSound)
            addLog("Закрыл дверь: \(door.name)")
            announce("Закрыл \(door.name).")
            refreshScreenState()
            return
        }

        _ = machine.open()
        audioCoordinator.playEffect(door.openSound)
        addLog("Открыл дверь: \(door.name)")
        announce("Открыл \(door.name). Чтобы пройти, нажми \(passCommandHint(for: door)).")
        refreshScreenState()
    }

    func tryPassThroughDoor(_ door: DoorDefinition) {
        if timedDoorConfiguration(for: door) != nil {
            let machine = gateMachine(for: door)

            if machine.isOpening {
                audioCoordinator.playBlockedMovement()
                announce("Калитка еще открывается. Дождись, пока она откроется.")
                return
            }

            if machine.isClosing {
                audioCoordinator.playBlockedMovement()
                announce("Калитка сейчас закрывается. Подожди немного.")
                return
            }

            guard machine.isOpen else {
                audioCoordinator.playBlockedMovement()
                announce("Калитка закрыта. Сначала открой ее.")
                return
            }

            passThroughDoor(door)
            return
        }

        let machine = doorMachine(for: door)

        guard !machine.isLocked else {
            addLog("Дверь заперта: \(door.name)")
            audioCoordinator.playBlockedMovement()
            announce(door.lockedText)
            return
        }

        guard machine.isOpen else {
            audioCoordinator.playBlockedMovement()
            announce("Дверь закрыта. Сначала открой ее.")
            return
        }

        passThroughDoor(door)
    }

    func describeCurrentFocus() {
        if let controlledCar = state.controlledCar {
            announce(controlledCarFullDescription(controlledCar))
            return
        }

        if let driveableCar = currentFocusDriveableCarContext() {
            let description: String
            if driveableCar.kind == .roadster {
                description = "Перед тобой \(driveableCar.title). В этой версии в него пока нельзя сесть, но его можно осмотреть как часть мира."
            } else if driveableCar.isOwned {
                description = parkedOwnedCarFullDescription(
                    state.parkedOwnedCars[driveableCar.id] ??
                    ParkedOwnedCarState(
                        id: driveableCar.id,
                        kind: driveableCar.kind,
                        title: driveableCar.title,
                        roomID: currentRoom.id,
                        worldPosition: driveableCar.worldPosition,
                        gridPosition: driveableCar.gridPosition,
                        headingRadians: 0,
                        directionLeftToRight: driveableCar.directionLeftToRight,
                        isEngineRunning: driveableCar.isEngineRunning
                    )
                )
            } else {
                description = "Перед тобой \(driveableCar.title). Если подойти вплотную и нажать E, можно сесть внутрь. После посадки мотор нужно завести отдельно ещё одним нажатием E."
            }
            announce(description)
            return
        }

        if currentFocusItem == nil,
           currentFocusDoor == nil,
           currentFocusStreetCarSnapshot() == nil,
           let heldAction = heldItemAction(for: .describe) {
            apply(heldAction)
            return
        }

        let text: String
        let focusedStreetCar = currentFocusStreetCarSnapshot()
        var streetCarDepartureID: UUID?

        if let item = currentFocusItem {
            text = item.fullDescriptionProvider(state)
        } else if let door = currentFocusDoor {
            let stateText = doorDescriptionStateText(for: door)
            text = "Перед тобой \(door.name). \(stateText)"
        } else {
            if let focusedStreetCar, focusedStreetCar.isInspectable {
                text = focusedStreetCar.fullDescription
                streetCarDepartureID = focusedStreetCar.id
            } else {
                text = currentFocusNode?.fullDescription ?? roomEmptyDescription()
            }
        }

        addLog("Описание: \(ui.focusTitle)")
        announce(text)
        if let streetCarDepartureID {
            scheduleStreetCarDeparture(afterDescribing: text, carID: streetCarDepartureID)
        } else {
            pendingStreetCarDepartureTask?.cancel()
            pendingStreetCarDepartureTask = nil
        }
    }

    func scheduleStreetCarDeparture(afterDescribing text: String, carID: UUID) {
        pendingStreetCarDepartureTask?.cancel()

        let delay = estimatedSpeechDuration(for: text) + 0.7
        pendingStreetCarDepartureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.audioCoordinator.triggerStreetCarDeparture(carID)
            self?.pendingStreetCarDepartureTask = nil
        }
    }

    func estimatedSpeechDuration(for text: String) -> TimeInterval {
        let letters = text.count
        let duration = 1.3 + (Double(letters) * 0.055)
        return min(14.0, max(2.4, duration))
    }

    func action(for trigger: ActionTrigger) -> ItemAction? {
        if trigger == .placeHeldItem,
           let action = bedItemWhileOnBed?.actionsProvider(state).first(where: { $0.trigger == trigger }) {
            return action
        }

        if let action = currentFocusItem?.actionsProvider(state).first(where: { $0.trigger == trigger }) {
            return action
        }

        if let action = heldItemAction(for: trigger) {
            return action
        }

        return bedItemWhileOnBed?.actionsProvider(state).first(where: { $0.trigger == trigger })
    }

    func heldItemAction(for trigger: ActionTrigger) -> ItemAction? {
        guard let heldItemID = state.player.heldItem?.itemID else {
            return nil
        }

        let actions: [ItemAction]
        switch heldItemID {
        case BedroomPillow.itemID:
            actions = BedroomPillow.heldActions(for: state)
        case KitchenKettle.itemID:
            actions = KitchenKettle.heldActions(for: state)
        case _ where KitchenMug.isMugItemID(heldItemID):
            actions = KitchenMug.heldActions(for: state, itemID: heldItemID)
        case GroceryStoreTeabag.itemID:
            actions = GroceryStoreTeabag.heldActions(for: state)
        case GroceryStoreSugar.itemID:
            actions = GroceryStoreSugar.heldActions(for: state)
        default:
            actions = []
        }

        return actions.first(where: { $0.trigger == trigger })
    }

    func inventoryQuickAction() -> ItemAction? {
        heldItemAction(for: .placeHeldItem) ?? heldItemAction(for: .throwItem)
    }

    func toggleInventory() {
        if inventoryMachine.isOpen {
            _ = inventoryMachine.close()
            setInventoryOpen(false)
        } else {
            _ = inventoryMachine.open()
            setInventoryOpen(true)
        }
        refreshScreenState()

        if inventoryMachine.isOpen {
            if let heldItem = state.player.heldItem {
                announce("Открыт инвентарь. В руках \(heldItem.name). E главное действие. F силовое действие. C положить рядом. R описание. Escape закрывает.")
            } else {
                announce("Инвентарь пуст.")
            }
        } else {
            announce("Инвентарь закрыт.")
        }
    }

    func handleInventoryCommand(_ command: GameCommand) {
        switch command {
        case .primaryAction:
            performInventoryAction(trigger: .primary, missingText: "Сейчас в инвентаре нет главного действия.")
        case .forceAction:
            performInventoryAction(trigger: .force, missingText: "Сейчас в инвентаре нет силового действия.")
        case .inventoryQuickAction:
            if let action = inventoryQuickAction() {
                apply(action)
            } else {
                announce("Сейчас в инвентаре нечего класть рядом.")
            }
        case .describeFocus:
            if let action = heldItemAction(for: .describe) {
                apply(action)
            } else if state.player.heldItem == nil {
                announce("Инвентарь пуст.")
            } else {
                announce(ui.inventoryText)
            }
        default:
            announce("Инвентарь открыт. Нажми Escape, чтобы закрыть.")
        }
    }

    func performInventoryAction(trigger: ActionTrigger, missingText: String) {
        guard let action = heldItemAction(for: trigger) else {
            announce(missingText)
            return
        }

        apply(action)
    }

    func apply(_ action: ItemAction) {
        // During stun: allow primary actions (bed, etc.) but block force/throw/place
        // Command-level blocking in handle() already restricts which commands work during stun.

        if let required = action.requiresHeldItemID, state.player.heldItem?.itemID != required {
            announce("Сейчас у тебя нет нужного предмета.")
            return
        }

        if let emptyHandsMessage = action.requiresEmptyHandsMessage, state.player.heldItem != nil {
            announce(emptyHandsMessage)
            return
        }

        if let specialText = handleSpecialInteraction(for: action) {
            poseMachine.sync(pose: state.player.pose)
            syncBedAnchorAfterAction()
            syncKettleBoilingTask()
            audioCoordinator.playEffect(action.sound)
            refreshScreenState()
            addLog(specialText)
            announce(specialText)
            return
        }

        action.stateMutation(&state)
        poseMachine.sync(pose: state.player.pose)

        if let producedItem = action.producesHeldItem {
            state.player.heldItem = producedItem
            if !poseMachine.isStanding, producedItem.itemID == BedroomPillow.itemID {
                state.player.focusedTarget = .item(BedroomBed.itemID)
            }
        }

        syncBedAnchorAfterAction()
        syncKettleBoilingTask()
        audioCoordinator.playEffect(action.sound)
        let extraReaction = neighbor.reactToLoudActionIfNeeded(for: action)

        if action.trigger == .throwItem {
            neighbor.performThrowDistraction()
        }

        refreshScreenState()
        addLog(action.resultText)
        if let extraReaction {
            addLog(extraReaction)
            announce("\(action.resultText) \(extraReaction)", delay: 0.7)
        } else {
            announce(action.resultText)
        }
    }

    func doorAtCurrentPosition() -> DoorDefinition? {
        guard let node = visibleNode(at: state.player.roomPosition) else { return nil }
        guard case let .door(id) = node.target else { return nil }
        return currentRoom.doors[id]
    }

    func passThroughDoor(_ door: DoorDefinition) {
        let targetRoom = rooms[door.targetRoomID] ?? currentRoom

        // Смена комнаты сбрасывает укрытие
        if neighbor.hidingSystem.isHiding {
            neighbor.hidingSystem.exitHiding()
            addLog("Ты вышел из укрытия.")
        }

        state.player.roomID = door.targetRoomID
        state.player.roomPosition = door.targetRoomPosition ?? targetRoom.spawnPosition
        state.player.focusedTarget = .none
        setPlayerPose(.standing)
        bedAnchorPosition = nil

        // Use reverb for door sound when entering hallway
        if door.targetRoomID == .hallway {
            audioCoordinator.playEffectWithReverb(door.sound)
        } else {
            audioCoordinator.playEffect(door.sound)
        }

        // Update hallway reverb flag
        audioCoordinator.hallwayReverbEnabled = (state.player.roomID == .hallway)

        refreshScreenState()
        addLog("Переход: \(targetRoom.title)")
        let prompt = currentShortPrompt()
        let text = prompt.isEmpty
            ? "Ты прошел через \(doorAccusativeName(for: door)). \(targetRoom.entryAnnouncement)"
            : "Ты прошел через \(doorAccusativeName(for: door)). \(targetRoom.entryAnnouncement) \(prompt)"
        announce(text)
    }

    func finishGame(
        roomTitle: String = "Улица",
        focusTitle: String = "Конец игры",
        text: String = "Конец. Ты вышел на улицу. Вы прошли игру, спасибо за внимание.",
        logLine: String = "Конец игры",
        ambientCue: AudioCueID? = nil,
        announcementDelay: TimeInterval = 0
    ) {
        neighbor.cancelNeighborTasks()
        doors.cancelGateTransitionTasks(resetMachines: true)
        cancelKettleBoilingTask(resetWaterState: false)
        carLifecycleTask?.cancel()
        carLifecycleTask = nil
        stopDrivingLoop()
        resetDrivingInput()
        state.controlledCar = nil
        state.parkedOwnedCars = [:]
        carLifecycleMachine.reset()
        audioCoordinator.stopControlledCarAudio()
        flowController.enter(.finished)
        ui.stage = flowController.currentStage
        state.player.focusedTarget = .none
        setPlayerPose(.standing)
        bedAnchorPosition = nil
        audioCoordinator.setTrafficEnabled(false)
        audioCoordinator.setStreetPresence(.off, fadeDuration: 0)
        audioCoordinator.playAmbient(ambientCue)
        self.ui.roomTitle = roomTitle
        self.ui.focusTitle = focusTitle
        ui.focusShortText = ""
        if let heldItem = state.player.heldItem {
            ui.holdText = "В руках: \(heldItem.name)."
        } else {
            ui.holdText = "Стоишь"
        }
        ui.statusText = text
        addLog(logLine)
        announce(text, delay: announcementDelay)
        onGameFinished?()
    }

    func performHideAction() {
        guard neighbor.hidingSystem.canHide(playerPosition: state.player.roomPosition, roomDef: currentRoom) else {
            announce("Здесь нет места, чтобы спрятаться.")
            return
        }

        if neighbor.hidingSystem.isHiding {
            announce("Ты уже спрячешься.")
            return
        }

        let spot = neighbor.hidingSystem.availableHidingSpots(playerPosition: state.player.roomPosition, roomDef: currentRoom).first!
        neighbor.hidingSystem.hide(in: spot)
        addLog("Спрячешься за \(spot.type == .inBed ? "кроватью" : "мебелью").")
        announce("Спрячешься. Нажми H или двинься, чтобы выйти из укрытия.")
        refreshScreenState()
    }

}
