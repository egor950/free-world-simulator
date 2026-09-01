# Архитектура «Симулятора свободного мира»

Этот документ описывает текущую архитектуру проекта по состоянию на ветку `main`. Он дополняет `README.md` обзором связей между основными подсистемами и практическими точками входа для разработки.

## 1. Общая схема

Проект — аудиоигра на Swift для macOS и iOS. Общая игровая логика находится в `Sources/Shared`, а платформенные точки входа разделены на `Sources/macOSApp` и `Sources/iOSApp`.

Упрощённая схема:

```text
macOS App / iOS App
        │
        ▼
  GameViewModel
        │
        ├── WorldRuntimeState
        ├── WorldBuilder → RoomDefinition → комнаты и объекты
        ├── DoorSystem / RoomTraversalMachine
        ├── InventoryMachine / PoseMachine
        ├── NeighborAIDirector
        ├── GameVehicleRuntime / системы машин
        ├── AudioCoordinator
        └── SpeechCoordinator

macOS debug / MCP
        │
        ▼
  StdioMCPServer
        │
        ▼
  EmbeddedGameRuntime / LiveGameBridge
        │
        ▼
  GameViewModel
```

Главная идея: `GameViewModel` является связующим слоем игрового runtime. Он не создаёт каждую сущность мира вручную, а получает готовое описание мира от `WorldBuilder` и делегирует специализированное поведение отдельным системам.

## 2. Игровое состояние

`Sources/Shared/GameViewModel/GameViewModel.swift` содержит `@MainActor final class GameViewModel`.

В нём находятся ссылки на ключевые подсистемы и текущее состояние `WorldRuntimeState`. При инициализации:

1. создаются или принимаются `SpeechCoordinator`, `AudioCoordinator` и `GameFlowController`;
2. вызывается `WorldBuilder.makeWorld()`;
3. игрок размещается в коридоре на стартовой позиции комнаты;
4. настраиваются наблюдатели уличного транспорта и системы соседей/дверей;
5. состояние UI синхронизируется с миром.

`GameViewModel` также является делегатом для некоторых подсистем. Например, через `DoorDelegate` он предоставляет текущую комнату, обновляет экранное состояние и получает/создаёт машину жизненного цикла двери.

## 3. Модель мира

Основные модели находятся в `Sources/Shared/WorldCore/WorldModels.swift`.

В текущей модели мира определены:

- `GameStage`: этапы `welcome`, `characterCreation`, `exploration`, `finished`;
- `RoomID`: `hallway`, `bedroom`, `livingRoom`, `kitchen`, `bathroom`, `street`, `mainStreet`, `groceryStore`, `teaRoom`;
- `GridPosition`: координаты объекта/игрока внутри пространства;
- `RoomMovementMode`: линейное перемещение или свободная сетка 4 направления;
- `FocusNode`: точка интереса с позицией, целью, короткой подсказкой и полным описанием;
- `FocusTarget`: дверь, предмет или отсутствие выбранной цели;
- состояния и конфигурации дверей и действий.

Мир собирается централизованно в `Sources/Shared/WorldCore/WorldBuilder.swift`. Сейчас `WorldBuilder.makeWorld()` регистрирует девять комнат и возвращает словарь `[RoomID: RoomDefinition]`.

## 4. Комнаты и предметы

Комнаты располагаются в `Sources/Shared/Rooms/`, а отдельные предметы представлены отдельными Swift-файлами согласно текущим правилам проекта.

Практическое правило: добавление новой комнаты должно проходить через её `RoomDefinition` и регистрацию в `WorldBuilder`. Новый предмет должен быть добавлен в соответствующую комнату и иметь собственное описание/идентификатор.

Идентификаторы мира используются как стабильные строки, например для комнат, предметов и дверных связей. Это особенно важно для отладочных и MCP-команд, где сущности адресуются по ID.

## 5. Двери, перемещение и состояния

Проект активно использует GameplayKit для state machine. В `GameViewModel` присутствуют, в частности, `DoorSystem`, `RoomTraversalMachine`, `PoseMachine` и `InventoryMachine`.

Правило проекта: жизненный цикл состояния должен быть представлен через `GKStateMachine`/`GKState`, а не через самодельный `enum State` с отдельной переменной `currentState`.

Это касается дверей, машин и других подсистем, где состояние имеет допустимые переходы.

## 6. Звук

Основная работа со звуком сосредоточена в:

```text
Sources/Shared/Audio/
```

`AudioCoordinator` отвечает за воспроизведение и синхронизацию звукового состояния мира. Озвучка текста вынесена в `SpeechCoordinator`.

Звуковые ресурсы находятся в `Resources/Audio/` и подключаются к целям проекта как ресурсы.

Для добавления нового звука текущая схема такая:

1. добавить аудиофайл в `Resources/Audio/`;
2. добавить соответствующий идентификатор в систему `AudioCueID`;
3. связать событие игрового мира с новым cue в соответствующем координаторе/системе.

Важно: короткие звуковые сигналы нельзя автоматически затухать через `afade`, если это ухудшает сам сигнал; это отдельно отмечено в `AGENTS.md` как правило проекта.

## 7. Уличный транспорт

Система машин находится в `Sources/Shared/Vehicles/` и связана с логикой уличного трафика.

`GameViewModel` хранит `GameVehicleRuntime`, а игровые действия автомобиля проходят через расширения `GameViewModel`, посвящённые миру и действиям транспорта.

Отдельный `StreetTrafficCoordinator` отвечает за движение и звуковое поведение уличного транспорта. Для припаркованных и управляемых машин существуют отдельные аудиокомпоненты.

Важный архитектурный принцип: состояния автомобилей также должны строиться через GameplayKit, поскольку жизненный цикл машины имеет последовательности состояний и допустимых переходов.

## 8. Сосед и AI

`NeighborAIDirector` реализует логику поведения соседа и взаимодействует с `GameViewModel` через `NeighborAIDelegate`.

Делегат предоставляет AI информацию о текущем этапе игры, комнате игрока, позиции, состоянии нахождения на улице и возможности уйти к машине. Благодаря этому AI не должен напрямую владеть всем игровым состоянием.

Для сложного поведения соседа используются отдельные машины состояний и специализированные системы.

## 9. MCP и живая игра

На macOS проект имеет отдельный путь управления игрой через MCP.

Основные компоненты:

```text
Sources/Shared/EmbeddedMCPServer/
Sources/Shared/LiveGameBridge/
Sources/MCPServer/
```

`MCPToolRuntime` определяет операции runtime: запуск/продолжение игры, нажатия команд, чтение состояния и логов, отладочные сценарии, телепортацию и `debug_world`.

`EmbeddedGameRuntime` реализует этот протокол и добавляет интервалы между командами, чтобы последовательные игровые действия не выполнялись слишком быстро.

`LiveGameBridge` создаёт и хранит экземпляр `GameViewModel`, принимает JSON-команды по локальному TCP-соединению и возвращает JSON-ответ. Мост также собирает озвученные фразы, игровой лог и собственный лог моста.

### Основные операции runtime

```text
start_game
continue_game
press
key_down
key_up
get_state
observe_game
get_phrases
get_log
list_debug_scenarios
run_debug_scenario
teleport
debug_world
```

При разработке игровых сценариев сначала стоит использовать существующие debug/MCP-механизмы, когда они уже позволяют воспроизвести нужное состояние или действие. Это соответствует правилам, записанным в `AGENTS.md`.

## 10. Сборка

Проект описан через `project.yml` и использует XcodeGen для генерации Xcode-проекта.

Поддерживаемые targets:

- `FreeWorldMac` — macOS-приложение;
- `FreeWorldiOS` — iOS-приложение;
- `FreeWorldMCP` — macOS-инструмент MCP;
- `FreeWorldVarispeedProbe` — отдельная проверка звука.

Генерация:

```bash
xcodegen generate
```

Сборка macOS:

```bash
xcodebuild -project FreeWorldSimulator.xcodeproj -scheme FreeWorldMac build
```

Сборка iOS Simulator:

```bash
xcodebuild -project FreeWorldSimulator.xcodeproj -scheme FreeWorldiOS -destination 'platform=iOS Simulator' build
```

Сборка MCP:

```bash
xcodebuild -project FreeWorldSimulator.xcodeproj -scheme FreeWorldMCP build
```

## 11. Куда идти при типичной задаче

| Задача | Точка входа |
|---|---|
| Добавить комнату | `Sources/Shared/Rooms/` + `WorldBuilder.swift` |
| Добавить предмет | соответствующая папка комнаты |
| Изменить игровое действие | `GameViewModel` и его extensions |
| Изменить перемещение | `GameViewModel` / traversal-системы |
| Изменить двери | `DoorSystem` и door state machines |
| Изменить звук | `Sources/Shared/Audio/` |
| Изменить машины | `Sources/Shared/Vehicles/` и `StreetTrafficCoordinator` |
| Изменить AI соседа | `Sources/Shared/NeighborAI/` |
| Изменить MCP-команды | `EmbeddedMCPServer/` и `LiveGameBridge/` |
| Изменить debug-сценарий | debug-extensions `GameViewModel` |

## 12. Правила безопасного изменения

Перед изменением сначала найдите существующую систему, которая уже отвечает за нужное поведение. Не дублируйте логику в `GameViewModel`, если для неё уже есть отдельный coordinator, runtime или state machine.

Для stateful-механик придерживайтесь GameplayKit и существующих паттернов проекта. После изменения проверяйте сборку соответствующего target и, когда это применимо, воспроизводите сценарий через MCP/debug-инструменты.

`AGENTS.md` остаётся источником более детальных локальных правил проекта и должен учитываться вместе с этой архитектурной схемой.
