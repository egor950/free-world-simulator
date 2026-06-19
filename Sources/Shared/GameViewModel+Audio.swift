import Foundation

extension GameViewModel {
    func maybeShowTutorial() {
        guard !UserDefaults.standard.bool(forKey: tutorialDefaultsKey) else {
            state.player.hasCompletedTutorial = true
            return
        }

        state.player.hasCompletedTutorial = true
        UserDefaults.standard.set(true, forKey: tutorialDefaultsKey)
        ui.isTutorialVisible = true

        if platformControls.shouldSpeakControlNames {
            ui.tutorialText = """
            Обучение. В квартире стрелки ведут тебя по дорожке комнаты, а на улице дают ходить во все четыре стороны. Q читает полное описание. E делает главное действие. F бьет или ломает. Пробел сбрасывает. Удержание E кладет предмет обратно.
            """
        } else {
            ui.tutorialText = """
            Обучение. Внизу экрана есть крупные кнопки для движения, описания и действий. Игра будет говорить только важные события, а не названия кнопок.
            """
        }

        announce(ui.tutorialText)
    }

    func announce(_ text: String, delay: TimeInterval = 0) {
        ui.statusText = text
        pendingAnnouncementTask?.cancel()

        guard delay > 0 else {
            speechCoordinator.speak(text)
            return
        }

        pendingAnnouncementTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.speechCoordinator.speak(text)
        }
    }

    func setSilentStatus(_ text: String) {
        ui.statusText = text
    }

    func announceDrivingHintIfNeeded(_ text: String, minimumGap: TimeInterval = 1.25) {
        ui.statusText = text
        let now = Date()
        let shouldSpeak = text != lastDrivingHintText || now.timeIntervalSince(lastDrivingHintAt) >= minimumGap
        guard shouldSpeak else { return }
        lastDrivingHintText = text
        lastDrivingHintAt = now
        speechCoordinator.speak(text)
    }

    func syncAudioWorldState() {
        guard ui.stage == .exploration else { return }

        audioCoordinator.playAmbient(currentRoom.ambientSound)
        audioCoordinator.setStepSurface(currentRoom.stepSurface)

        switch currentRoom.id {
        case .street:
            audioCoordinator.setStreetPresence(.courtyard)
            audioCoordinator.setTrafficEnabled(true)
            audioCoordinator.setStreetListenerPosition(state.player.roomPosition, roomID: .street)
        case .mainStreet:
            audioCoordinator.setStreetPresence(.wideOpenStreet)
            audioCoordinator.setTrafficEnabled(true)
            audioCoordinator.setStreetListenerPosition(state.player.roomPosition, roomID: .mainStreet)
        case .bathroom:
            let streetDoorOpen = currentRoom.doors["bathroom.door.street"].map { isDoorOpened($0) } ?? false
            audioCoordinator.setStreetPresence(streetDoorOpen ? .insideOpenDoor : .insideClosedDoor)
            audioCoordinator.setTrafficEnabled(false)
        default:
            audioCoordinator.setStreetPresence(.off)
            audioCoordinator.setTrafficEnabled(false)
        }

        audioCoordinator.syncParkedOwnedCarAudio(
            cars: Array(state.parkedOwnedCars.values),
            listenerRoomID: currentRoom.id,
            listenerPosition: state.player.roomPosition,
            controlledCar: state.controlledCar
        )
    }
}
