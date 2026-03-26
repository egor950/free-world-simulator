import Foundation

@MainActor
private final class PlaytestSession {
    private(set) var failures = 0
    private var lines: [String] = []
    private var stepCounter = 0

    func run() async {
        let game = makeStartedGame()

        log("=== Старт автопроверки ===")
        snapshot(game, title: "Игра запущена")

        runDoorChainScenario(game)
        runDoorToggleScenario()
        runStreetScenario()
        runStreetBoundaryScenario()
        runGroceryNavigationScenario()
        runNeighborNoiseScenario()
        await runKitchenWaterScenario()
        await runCarDrivingScenario()

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
        let boundaryText = game.statusText.lowercased()
        expect(
            boundaryText.contains("край дороги") || boundaryText.contains("калитка закрыта"),
            "Улица ограничивает путь вперед",
            "На краю улицы не сработало сообщение об ограничении"
        )
    }

    private func runGroceryNavigationScenario() {
        log("=== Сценарий 5: маяк ведет от калитки до прилавка продуктового ===")
        let game = makeStartedGame()
        _ = game.runDebugScenario(named: "main_street_entry")

        press(game, .locationMenuToggle, "Открыть меню маяка")
        press(game, .locationMenuConfirm, "Включить маяк продуктового")

        for _ in 0..<120 {
            if game.roomTitle == "Продуктовый" {
                break
            }

            let hint = game.currentNavigationBeaconHint()?.lowercased() ?? ""
            if hint.contains("вправо") {
                press(game, .moveRight, "Иду вправо по маяку")
            } else if hint.contains("влево") {
                press(game, .moveLeft, "Иду влево по маяку")
            } else if hint.contains("назад") || hint.contains("позади") {
                press(game, .moveBackward, "Иду назад по маяку")
            } else {
                press(game, .moveForward, "Иду вперед по маяку")
            }

            if game.focusTitle.lowercased().contains("дверь продуктового"),
               game.focusShortText.lowercased().contains("закрыта") {
                press(game, .primaryAction, "Открыть дверь продуктового")
            }
        }

        expect(
            game.roomTitle == "Продуктовый",
            "Маяк довел до магазина",
            "Маршрут по маяку не довел до магазина"
        )

        for _ in 0..<40 {
            if game.focusTitle.lowercased().contains("продавец") {
                break
            }

            let hint = game.currentNavigationBeaconHint()?.lowercased() ?? ""
            if hint.contains("вправо") {
                press(game, .moveRight, "Иду вправо к прилавку")
            } else if hint.contains("влево") {
                press(game, .moveLeft, "Иду влево к прилавку")
            } else if hint.contains("назад") || hint.contains("позади") {
                press(game, .moveBackward, "Иду назад к прилавку")
            } else {
                press(game, .moveForward, "Иду вперед к прилавку")
            }
        }

        expect(
            game.focusTitle.lowercased().contains("продавец"),
            "Маяк довел до прилавка",
            "После входа в магазин маяк не довел до прилавка"
        )
    }

    private func runNeighborNoiseScenario() {
        log("=== Сценарий 5: соседи реагируют на шум ===")
        let game = makeStartedGame()

        game.debugMovePlayer(to: .livingRoom, position: GridPosition(x: 4, y: 1))
        press(game, .forceAction, "Разбить телевизор")
        expect(
            game.neighborEncounterMachine.isWarned,
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
            game.neighborEncounterMachine.isDoorbellRaised,
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
            game.neighborBreakInTask != nil,
            "После третьего удара реально запускается таймер штурма",
            "После третьего громкого удара состояние взлома поднялось, но сам таймер штурма не стартовал"
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

    private func runKitchenWaterScenario() async {
        log("=== Сценарий 6: чайник, кран, подставка и кружка ===")
        let game = makeStartedGame()

        game.debugMovePlayer(to: .kitchen, position: GridPosition(x: 4, y: 2))
        snapshot(game, title: "Стою у чайника")
        expect(
            game.focusTitle.lowercased().contains("чайник"),
            "Отладочный переход поставил к чайнику",
            "Не удалось поставить игрока к чайнику"
        )

        press(game, .primaryAction, "Взять чайник")
        expect(
            game.holdText.lowercased().contains("чайник"),
            "Чайник оказался в руках",
            "После взятия чайник не оказался в руках"
        )

        press(game, .primaryAction, "Открыть крышку чайника")
        expect(
            game.statusText.lowercased().contains("открыл крышку"),
            "Крышка чайника открылась",
            "Не получилось открыть крышку чайника"
        )

        game.debugMovePlayer(to: .bathroom, position: GridPosition(x: 2, y: 1))
        snapshot(game, title: "Стою у крана")
        expect(
            game.focusTitle.lowercased().contains("кран"),
            "Отладочный переход поставил к крану",
            "Не удалось поставить игрока к крану"
        )

        press(game, .primaryAction, "Налить воду в чайник")
        expect(
            game.statusText.lowercased().contains("налил воду"),
            "Вода набралась в чайник",
            "Не получилось налить воду в чайник"
        )

        game.debugMovePlayer(to: .kitchen, position: GridPosition(x: 3, y: 1))
        snapshot(game, title: "Стою у подставки чайника")
        expect(
            game.focusTitle.lowercased().contains("подставка"),
            "Отладочный переход поставил к подставке чайника",
            "Не удалось поставить игрока к подставке"
        )

        press(game, .placeHeldItem, "Поставить чайник на подставку")
        expect(
            game.focusTitle.lowercased().contains("подставка"),
            "После установки чайника фокус остался на подставке",
            "После установки чайника подставка не осталась в фокусе"
        )

        press(game, .primaryAction, "Включить чайник")
        expect(
            game.statusText.lowercased().contains("начинает греться"),
            "Чайник включился и греется",
            "После включения чайника не появилось сообщение о нагреве"
        )

        let boilWait =
            max(
                KitchenStove.kettleBaseHeatDuration - game.audioCoordinator.duration(of: .kettleHeatFinish),
                game.audioCoordinator.duration(of: .kettleHeatStart) + KitchenStove.minimumLoopDuration
            ) + game.audioCoordinator.duration(of: .kettleHeatFinish) + 0.8
        try? await Task.sleep(nanoseconds: UInt64(boilWait * 1_000_000_000))
        snapshot(game, title: "Жду, пока вода закипит")
        expect(
            game.statusText.lowercased().contains("закипела"),
            "Автоматическое кипячение завершилось",
            "Вода в чайнике не закипела автоматически"
        )

        press(game, .placeHeldItem, "Снять чайник с подставки")
        expect(
            game.holdText.lowercased().contains("чайник"),
            "После снятия чайник снова в руках",
            "После снятия чайник не вернулся в руки"
        )

        game.debugMovePlayer(to: .kitchen, position: GridPosition(x: 2, y: 1))
        snapshot(game, title: "Стою у кружки")
        expect(
            game.focusTitle.lowercased().contains("кружка"),
            "Отладочный переход поставил к кружке",
            "Не удалось поставить игрока к кружке"
        )

        press(game, .primaryAction, "Налить кипяток в кружку")
        expect(
            game.statusText.lowercased().contains("налил кипяток"),
            "Кипяток перелился в кружку",
            "Не получилось налить кипяток в кружку"
        )

        press(game, .describeFocus, "Осмотреть кружку")
        expect(
            game.statusText.lowercased().contains("горячая вода"),
            "Описание кружки показывает горячую воду",
            "После наливания описание кружки не обновилось"
        )
    }

    private func runCarDrivingScenario() async {
        log("=== Сценарий 7: посадка в машину, короткая поездка и повторная посадка ===")
        let game = makeStartedGame()

        _ = game.runDebugScenario(named: "street_parked_car")
        try? await Task.sleep(nanoseconds: 300_000_000)

        expect(
            game.currentFocusDriveableCarContext() != nil,
            "Отладочная машина доступна для посадки",
            "Не удалось получить доступную припаркованную машину"
        )

        press(game, .primaryAction, "Сесть в машину")
        try? await Task.sleep(nanoseconds: 2_400_000_000)

        guard let controlledCar = game.state.controlledCar else {
            expect(false, "После посадки появилась машина игрока", "После посадки машина не перешла под управление игрока")
            return
        }

        expect(
            controlledCar.engineState == .running,
            "После посадки мотор уже работает",
            "После полной посадки мотор не оказался в состоянии running"
        )

        let controlledCarID = controlledCar.id
        let startZ = controlledCar.worldPosition.z
        await hold(game, .moveForward, duration: 3.6, title: "Держу газ до калитки")

        let movedZ = game.state.controlledCar?.worldPosition.z ?? startZ
        expect(
            movedZ > startZ + 1.0,
            "Машина реально поехала вперед",
            "После нескольких нажатий газа машина почти не сдвинулась"
        )
        expect(
            (game.state.controlledCar?.worldPosition.z ?? 0) >= 16.9,
            "Машина стабильно доехала до калитки",
            "Даже на удержании газа машина не дошла до линии калитки"
        )
        expect(
            game.statusText.lowercased().contains("калитк"),
            "У закрытой калитки есть понятная подсказка",
            "У закрытой калитки игра не подсказала, почему машина остановилась"
        )

        for _ in 0..<8 {
            press(game, .moveBackward, "Тормоз")
            try? await Task.sleep(nanoseconds: 220_000_000)
            if abs(game.state.controlledCar?.speed ?? 0) <= 0.35 {
                break
            }
        }

        let reverseStartZ = game.state.controlledCar?.worldPosition.z ?? 0
        await hold(game, .moveBackward, duration: 0.18, title: "Коротко держу тормоз у калитки")
        let reverseAfterShortHold = game.state.controlledCar?.worldPosition.z ?? reverseStartZ
        expect(
            reverseAfterShortHold >= reverseStartZ - 0.2,
            "Короткое нажатие назад у калитки не уводит машину далеко назад",
            "После короткого нажатия назад машина слишком резко откатилась от калитки"
        )

        press(game, .primaryAction, "Выйти из машины")
        try? await Task.sleep(nanoseconds: 1_700_000_000)

        expect(
            game.state.controlledCar == nil,
            "После выхода управление машиной снято",
            "После полного выхода игрок всё ещё числится внутри машины"
        )
        expect(
            game.state.parkedOwnedCars[controlledCarID] != nil,
            "Оставленная машина осталась в мире",
            "После выхода машина не сохранилась как оставленная"
        )

        press(game, .primaryAction, "Снова сесть в ту же машину")
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        expect(
            game.state.controlledCar?.id == controlledCarID,
            "Повторная посадка возвращает ту же машину",
            "После повторной посадки игрок не получил ту же машину обратно"
        )
        expect(
            game.state.controlledCar?.engineState == .running,
            "При повторной посадке мотор остаётся заведённым",
            "После повторной посадки мотор не оказался в состоянии running"
        )
    }

    private func hold(_ game: GameViewModel, _ command: GameCommand, duration: TimeInterval, title: String) async {
        game.handleKeyboardInput(.press(command))
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        game.handleKeyboardInput(.release(command))
        snapshot(game, title: title)
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
    await session.run()
    exit(session.failures > 0 ? 1 : 0)
}

dispatchMain()
