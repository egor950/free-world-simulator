import Foundation

@MainActor
private final class PlaytestSession {
    private(set) var failures = 0
    private var lines: [String] = []
    private var stepCounter = 0

    func run() {
        let game = makeStartedGame()

        log("=== Старт автопроверки ===")
        snapshot(game, title: "Игра запущена")

        runDoorChainScenario(game)
        runDoorToggleScenario()
        runStreetScenario()
        runStreetBoundaryScenario()
        runNeighborNoiseScenario()

        log("=== Итог ===")
        if failures == 0 {
            log("Все проверки пройдены.")
        } else {
            log("Провалено проверок: \(failures)")
        }

        let savedPath = saveLog()
        log("Полный лог сохранен: \(savedPath)")
    }

    private func runDoorChainScenario(_ game: GameViewModel) {
        log("=== Сценарий 1: проход по цепочке комнат вперед ===")

        walkToDoorAndPass(game, doorName: "дверь в спальню", expectedRoom: "Спальня")
        walkToDoorAndPass(game, doorName: "дверь в гостиную", expectedRoom: "Гостиная")
        walkToDoorAndPass(game, doorName: "дверь на кухню", expectedRoom: "Кухня")
        walkToDoorAndPass(game, doorName: "дверь в ванную", expectedRoom: "Ванная")
    }

    private func runDoorToggleScenario() {
        log("=== Сценарий 2: открыть/закрыть/открыть дверь ===")
        let game = makeStartedGame()
        walkToBathroom(game)
        moveUntilFocus(game, contains: "дверь на улицу", command: .moveForward, limit: 20)

        if game.focusShortText.lowercased().contains("открыта") {
            press(game, .primaryAction, "Подготовка: закрыть открытую дверь")
        }

        press(game, .primaryAction, "Открыть дверь")
        expect(game.focusShortText.lowercased().contains("открыта"), "Дверь открылась", "После открытия дверь не стала открытой")

        press(game, .primaryAction, "Закрыть дверь")
        expect(game.focusShortText.lowercased().contains("закрыта"), "Дверь закрылась", "После закрытия дверь не стала закрытой")

        press(game, .primaryAction, "Открыть дверь снова")
        expect(game.focusShortText.lowercased().contains("открыта"), "Дверь снова открылась", "После повторного открытия дверь не открылась")
    }

    private func runStreetScenario() {
        log("=== Сценарий 3: выйти на улицу и вернуться ===")
        let game = makeStartedGame()
        walkToBathroom(game)

        moveUntilFocus(game, contains: "дверь на улицу", command: .moveForward, limit: 20)
        expect(game.focusTitle.lowercased().contains("дверь на улицу"),
               "Нашел дверь на улицу",
               "Не удалось дойти до двери на улицу")

        press(game, .primaryAction, "Открыть дверь на улицу")
        expect(game.focusShortText.lowercased().contains("открыта"),
               "Дверь на улицу открыта",
               "Дверь на улицу не открылась")

        press(game, .moveForward, "Выйти на улицу")
        expect(game.roomTitle == "Улица",
               "Переход на улицу",
               "После выхода ожидалась улица, а сейчас «\(game.roomTitle)»")

        let streetStart = game.debugRoomPosition
        press(game, .moveLeft, "Шаг влево по двору")
        expect(game.debugRoomPosition.x == streetStart.x - 1,
               "На улице шаг влево работает",
               "На улице шаг влево не сдвинул позицию")

        press(game, .moveRight, "Вернуться к двери во двор")
        expect(game.debugRoomPosition == streetStart,
               "На улице шаг вправо вернул к двери",
               "На улице шаг вправо не вернул к двери")

        press(game, .moveForward, "Шаг вперед по двору")
        expect(game.debugRoomPosition.y == streetStart.y - 1,
               "На улице шаг вперед работает",
               "На улице шаг вперед не сдвинул позицию")

        press(game, .moveBackward, "Вернуться к двери из двора")
        press(game, .moveBackward, "Вернуться в ванную")
        expect(game.roomTitle == "Ванная",
               "Возврат с улицы в ванную",
               "После возврата ожидалась ванная, а сейчас «\(game.roomTitle)»")
    }

    private func runStreetBoundaryScenario() {
        log("=== Сценарий 4: край улицы не пускает дальше ===")
        let game = makeStartedGame()
        walkToBathroom(game)
        moveUntilFocus(game, contains: "дверь на улицу", command: .moveForward, limit: 20)
        press(game, .primaryAction, "Открыть дверь на улицу")
        press(game, .moveForward, "Выйти на улицу")

        for _ in 0..<14 {
            press(game, .moveForward, "Иду к краю дороги")
        }

        press(game, .moveForward, "Упереться в край дороги")
        expect(game.statusText.lowercased().contains("край дороги"),
               "Улица ограничивает путь вперед",
               "На краю улицы не сработало сообщение об ограничении")
    }

    private func runNeighborNoiseScenario() {
        log("=== Сценарий 5: соседи реагируют на шум ===")
        let game = makeStartedGame()

        game.debugMovePlayer(to: .livingRoom, position: GridPosition(x: 4, y: 1))
        press(game, .forceAction, "Разбить телевизор")
        expect(
            game.state.flag(itemID: GameViewModel.NeighborNoise.worldID, key: GameViewModel.NeighborNoise.warnedFlag),
            "Первый громкий удар поднимает предупреждение соседей",
            "После первого громкого удара соседи не перешли в предупреждение"
        )
        expect(
            game.statusText.lowercased().contains("что творишь"),
            "После первого удара слышно предупреждение соседей",
            "После первого громкого удара не появилось предупреждение соседей"
        )

        game.debugMovePlayer(to: .livingRoom, position: GridPosition(x: 4, y: 2))
        press(game, .forceAction, "Разломать стол")
        expect(
            game.state.flag(itemID: GameViewModel.NeighborNoise.worldID, key: GameViewModel.NeighborNoise.doorbellFlag),
            "Второй громкий удар поднимает звонок соседей",
            "После второго громкого удара соседи не перешли к звонку"
        )
        expect(
            game.statusText.lowercased().contains("злой звонок"),
            "После второго удара запускается звонок соседей",
            "После второго громкого удара не появился звонок соседей"
        )

        game.debugMovePlayer(to: .kitchen, position: GridPosition(x: 5, y: 2))
        press(game, .forceAction, "Грохнуть по холодильнику")
        expect(
            game.neighborEncounterMachine.isBreakInActive,
            "Третий громкий удар запускает взлом двери",
            "После третьего громкого удара соседи не перешли к взлому двери"
        )
        expect(
            game.statusText.lowercased().contains("ломай дверь"),
            "После третьего удара соседи идут на штурм",
            "После третьего громкого удара не запустился штурм соседей"
        )

        _ = game.runDebugScenario(named: "hallway_neighbor_door")
        expect(
            game.focusTitle.lowercased().contains("входная дверь"),
            "Отладочная сцена соседской двери ставит прямо к двери",
            "Отладочная сцена соседской двери не поставила игрока к двери"
        )
    }

    private func walkToDoorAndPass(_ game: GameViewModel, doorName: String, expectedRoom: String) {
        moveUntilFocus(game, contains: doorName, limit: 50)
        expect(game.focusTitle.lowercased().contains(doorName.lowercased()),
               "Нашел \(doorName)",
               "Не удалось дойти до \(doorName)")

        press(game, .primaryAction, "Открыть \(doorName)")
        expect(game.focusShortText.lowercased().contains("открыта"),
               "\(doorName) открыта",
               "\(doorName) не открылась")

        press(game, .moveForward, "Пройти через \(doorName)")
        expect(game.roomTitle == expectedRoom,
               "Переход в комнату «\(expectedRoom)»",
               "После двери ожидалась комната «\(expectedRoom)», а сейчас «\(game.roomTitle)»")
    }

    private func walkToBathroom(_ game: GameViewModel) {
        walkToDoorAndPass(game, doorName: "дверь в спальню", expectedRoom: "Спальня")
        walkToDoorAndPass(game, doorName: "дверь в гостиную", expectedRoom: "Гостиная")
        walkToDoorAndPass(game, doorName: "дверь на кухню", expectedRoom: "Кухня")
        walkToDoorAndPass(game, doorName: "дверь в ванную", expectedRoom: "Ванная")
    }

    private func makeStartedGame() -> GameViewModel {
        let game = GameViewModel(
            speechCoordinator: SpeechCoordinator(isMuted: true),
            audioCoordinator: AudioCoordinator(isMuted: true),
            movementStepInterval: 0
        )

        game.continueFromWelcome()
        game.selectedCharacterKind = .man
        game.characterName = "Тестер"
        game.finishCharacterCreation()
        return game
    }

    private func moveUntilFocus(_ game: GameViewModel, contains text: String, command: GameCommand = .moveForward, limit: Int) {
        var steps = 0
        while !game.focusTitle.lowercased().contains(text.lowercased()) && steps < limit {
            press(game, command, "Иду к «\(text)»")
            steps += 1
        }
    }

    private func press(_ game: GameViewModel, _ command: GameCommand, _ title: String) {
        game.handle(command)
        snapshot(game, title: title)
    }

    private func expect(_ condition: Bool, _ okText: String, _ failText: String) {
        if condition {
            log("[OK] \(okText)")
        } else {
            failures += 1
            log("[FAIL] \(failText)")
        }
    }

    private func snapshot(_ game: GameViewModel, title: String) {
        stepCounter += 1
        log("")
        log("Шаг \(stepCounter): \(title)")
        log("Комната: \(game.roomTitle)")
        log("Позиция: x=\(game.debugRoomPosition.x), y=\(game.debugRoomPosition.y)")
        log("Рядом: \(game.focusTitle)")
        log("Коротко: \(game.focusShortText)")
        log("Статус: \(game.statusText)")
        if let last = game.eventLog.first {
            log("Последнее событие: \(last)")
        }
    }

    private func log(_ text: String) {
        lines.append(text)
        print(text)
    }

    @discardableResult
    private func saveLog() -> String {
        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        let logsDirectory = URL(fileURLWithPath: cwd).appendingPathComponent("playtest_logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        let latestURL = logsDirectory.appendingPathComponent("full_playtest_latest.log")
        let stampedURL = logsDirectory.appendingPathComponent("full_playtest_\(timestamp).log")
        let content = lines.joined(separator: "\n")

        try? content.write(to: latestURL, atomically: true, encoding: .utf8)
        try? content.write(to: stampedURL, atomically: true, encoding: .utf8)
        return latestURL.path
    }
}

Task { @MainActor in
    let session = PlaytestSession()
    session.run()
    exit(session.failures > 0 ? 1 : 0)
}

dispatchMain()
