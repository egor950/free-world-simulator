import Foundation

extension GameViewModel {
    func performPrimaryAction() {
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
            handleNeighborDoor()
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
            audioCoordinator.playEffect(door.sound ?? .obstacleThud)
            addLog("Закрыл дверь: \(door.name)")
            announce("Закрыл \(door.name).")
            refreshScreenState()
            return
        }

        _ = machine.open()
        audioCoordinator.playEffect(door.sound ?? .obstacleThud)
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

        addLog("Описание: \(focusTitle)")
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

        return bedItemWhileOnBed?.actionsProvider(state).first(where: { $0.trigger == trigger })
    }

    func heldItemAction(for trigger: ActionTrigger) -> ItemAction? {
        guard state.player.heldItem?.itemID == BedroomPillow.itemID else {
            return nil
        }

        return BedroomPillow.heldActions(for: state).first(where: { $0.trigger == trigger })
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
                announce(inventoryText)
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
        if let required = action.requiresHeldItemID, state.player.heldItem?.itemID != required {
            announce("Сейчас у тебя нет нужного предмета.")
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
        audioCoordinator.playEffect(action.sound)
        let extraReaction = reactToLoudActionIfNeeded(for: action)
        refreshScreenState()
        addLog(action.resultText)
        if let extraReaction {
            addLog(extraReaction)
            announce("\(action.resultText) \(extraReaction)", delay: 0.7)
        } else {
            announce(action.resultText)
        }
    }

    func doorLinkID(for door: DoorDefinition) -> String {
        let ids = [state.player.roomID.rawValue, door.targetRoomID.rawValue].sorted()
        return ids.joined(separator: "|")
    }

    func timedDoorConfiguration(for door: DoorDefinition) -> TimedDoorTransitionConfiguration? {
        guard case let .timedGate(configuration) = door.interactionStyle else {
            return nil
        }

        return configuration
    }

    func doorMachine(for door: DoorDefinition) -> DoorLifecycleMachine {
        let linkID = doorLinkID(for: door)

        if let machine = doorLifecycleMachines[linkID] {
            machine.sync(staticState: door.state)
            return machine
        }

        let machine = DoorLifecycleMachine(staticState: door.state)
        doorLifecycleMachines[linkID] = machine
        return machine
    }

    func gateMachine(for door: DoorDefinition) -> GateLifecycleMachine {
        let linkID = doorLinkID(for: door)

        if let machine = gateLifecycleMachines[linkID] {
            return machine
        }

        let machine = GateLifecycleMachine()
        gateLifecycleMachines[linkID] = machine
        return machine
    }

    func cancelGateTransitionTasks(resetMachines: Bool) {
        gateTransitionTasks.values.forEach { $0.cancel() }
        gateTransitionTasks.removeAll()

        if resetMachines {
            gateLifecycleMachines.removeAll()
        }
    }

    func isDoorOpened(_ door: DoorDefinition) -> Bool {
        if timedDoorConfiguration(for: door) != nil {
            return gateMachine(for: door).isOpen
        }
        return doorMachine(for: door).isOpen
    }

    func doorAtCurrentPosition() -> DoorDefinition? {
        guard let node = visibleNode(at: state.player.roomPosition) else { return nil }
        guard case let .door(id) = node.target else { return nil }
        return currentRoom.doors[id]
    }

    func doorActionTitle(for door: DoorDefinition) -> String {
        if timedDoorConfiguration(for: door) != nil {
            let machine = gateMachine(for: door)
            if machine.isOpening {
                return "Открывается..."
            }
            if machine.isClosing {
                return "Закрывается..."
            }
            return machine.isOpen ? "Закрыть калитку" : "Открыть калитку"
        }

        let machine = doorMachine(for: door)
        if machine.isLocked {
            return "Проверить дверь"
        }
        return machine.isOpen ? "Закрыть" : "Открыть"
    }

    func doorDescriptionStateText(for door: DoorDefinition) -> String {
        if let configuration = timedDoorConfiguration(for: door) {
            let machine = gateMachine(for: door)
            if machine.isOpening {
                return "Она открывается. Сначала дождись конца звука, потом уже проходи."
            }
            if machine.isClosing {
                return "Она закрывается. Пока идет звук, подожди немного."
            }
            if machine.isOpen {
                return "Она открыта. Нажми \(passCommandHint(for: door)), чтобы пройти, или действие, чтобы закрыть."
            }
            _ = configuration
            return "Она закрыта. Нажми действие, чтобы открыть."
        }

        if door.state == .locked {
            return "Она заперта."
        }

        if isDoorOpened(door) {
            return "Она открыта. Нажми \(passCommandHint(for: door)), чтобы пройти, или действие, чтобы закрыть."
        }

        return "Она закрыта. Нажми действие, чтобы открыть."
    }

    func handleTimedDoorAction(_ door: DoorDefinition, configuration: TimedDoorTransitionConfiguration) {
        let machine = gateMachine(for: door)

        if machine.isOpening {
            announce("Калитка уже открывается. Подожди немного.")
            return
        }

        if machine.isClosing {
            announce("Калитка уже закрывается. Подожди немного.")
            return
        }

        if machine.isOpen {
            guard machine.beginClosing() else { return }
            audioCoordinator.playEffect(configuration.closeCue)
            addLog("Калитка закрывается: \(door.name)")
            announce("Закрываешь \(doorAccusativeName(for: door)).")
            refreshScreenState()
            scheduleTimedDoorCompletion(for: door, isOpening: false, duration: configuration.closeDuration)
            return
        }

        guard machine.beginOpening() else { return }
        audioCoordinator.playEffect(configuration.openCue)
        addLog("Калитка открывается: \(door.name)")
        announce("Открываешь \(doorAccusativeName(for: door)). Подожди немного.")
        refreshScreenState()
        scheduleTimedDoorCompletion(for: door, isOpening: true, duration: configuration.openDuration)
    }

    func scheduleTimedDoorCompletion(for door: DoorDefinition, isOpening: Bool, duration: TimeInterval) {
        let linkID = doorLinkID(for: door)
        gateTransitionTasks[linkID]?.cancel()

        gateTransitionTasks[linkID] = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }

            let machine = self.gateMachine(for: door)
            if isOpening {
                guard machine.finishOpening() else { return }
                self.addLog("Калитка открыта: \(door.name)")
                self.refreshScreenState()
                self.announce("Калитка открыта. Теперь можно пройти.")
            } else {
                guard machine.finishClosing() else { return }
                self.addLog("Калитка закрыта: \(door.name)")
                self.refreshScreenState()
                self.announce("Калитка закрыта.")
            }

            self.gateTransitionTasks[linkID] = nil
        }
    }

    func passThroughDoor(_ door: DoorDefinition) {
        let targetRoom = rooms[door.targetRoomID] ?? currentRoom
        state.player.roomID = door.targetRoomID
        state.player.roomPosition = door.targetRoomPosition ?? targetRoom.spawnPosition
        state.player.focusedTarget = .none
        setPlayerPose(.standing)
        bedAnchorPosition = nil
        audioCoordinator.playEffect(door.sound)
        refreshScreenState()
        addLog("Переход: \(targetRoom.title)")
        let prompt = currentShortPrompt()
        let text = prompt.isEmpty
            ? "Ты прошел через \(doorAccusativeName(for: door)). \(targetRoom.entryAnnouncement)"
            : "Ты прошел через \(doorAccusativeName(for: door)). \(targetRoom.entryAnnouncement) \(prompt)"
        announce(text)
    }

    func passCommandHint(for door: DoorDefinition) -> String {
        guard currentTraversalMode == .freeGrid4Way else {
            return "вперед"
        }

        let position = state.player.roomPosition
        if position.y == 0 {
            return "вперед"
        }
        if position.y == currentRoom.height - 1 {
            return "назад"
        }
        if position.x == 0 {
            return "влево"
        }
        if position.x == currentRoom.width - 1 {
            return "вправо"
        }

        return "вперед"
    }

    func doorAccusativeName(for door: DoorDefinition) -> String {
        switch door.name {
        case "калитка":
            return "калитку"
        default:
            return door.name
        }
    }

    func finishGame(
        roomTitle: String = "Улица",
        focusTitle: String = "Конец игры",
        text: String = "Конец. Ты вышел на улицу. Вы прошли игру, спасибо за внимание.",
        logLine: String = "Конец игры",
        ambientCue: AudioCueID? = nil,
        announcementDelay: TimeInterval = 0
    ) {
        cancelNeighborTasks()
        cancelGateTransitionTasks(resetMachines: true)
        flowController.enter(.finished)
        stage = flowController.currentStage
        state.player.focusedTarget = .none
        setPlayerPose(.standing)
        bedAnchorPosition = nil
        audioCoordinator.setTrafficEnabled(false)
        audioCoordinator.setStreetPresence(.off, fadeDuration: 0)
        audioCoordinator.playAmbient(ambientCue)
        self.roomTitle = roomTitle
        self.focusTitle = focusTitle
        focusShortText = ""
        if let heldItem = state.player.heldItem {
            holdText = "В руках: \(heldItem.name)."
        } else {
            holdText = "Стоишь"
        }
        statusText = text
        addLog(logLine)
        announce(text, delay: announcementDelay)
        onGameFinished?()
    }
}
