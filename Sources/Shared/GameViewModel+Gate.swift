import Foundation

extension GameViewModel {
    func timedDoorConfiguration(for door: DoorDefinition) -> TimedDoorTransitionConfiguration? {
        guard case let .timedGate(configuration) = door.interactionStyle else {
            return nil
        }

        return configuration
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
        if timedDoorConfiguration(for: door) != nil {
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
}
