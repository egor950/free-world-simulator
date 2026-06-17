# PROJECT KNOWLEDGE BASE

**Generated:** 2026-06-18
**Commit:** 7e7cbe1
**Branch:** main

## OVERVIEW
Аудиоигра на Swift про свободное перемещение по квартире и двору. Текстовый мир с озвучкой, предметами, дверями и машинами. Mac + iOS.

## STRUCTURE
```
FreeWorldSimulator/
├── Sources/
│   ├── Shared/          # Вся игровая логика (19 файлов)
│   │   ├── GameViewModel+*.swift  # Расширения: Actions, Movement, Audio, Debug, etc.
│   │   ├── AudioCoordinator.swift # Движок звука (587 строк)
│   │   ├── SpeechCoordinator.swift # Озвучка текста
│   │   ├── StreetTrafficCoordinator.swift # Уличные машины (1660 строк!)
│   │   ├── EmbeddedMCPServer.swift # MCP-сервер внутри приложения
│   │   ├── LiveGameBridge.swift   # Связь MCP ↔ игра
│   │   ├── Vehicles/             # Система машин (9 файлов)
│   │   ├── WorldCore/            # Ядро мира (5 файлов)
│   │   └── Rooms/                # Комнаты и предметы (8 подпапок)
│   ├── macOSApp/        # Точка входа macOS
│   ├── iOSApp/          # Точка входа iOS
│   ├── MCPServer/       # Внешний MCP-сервер
│   └── VarispeedProbe/  # Тест звука
├── Resources/
│   └── Audio/           # 58 mp3 файлов
└── FreeWorldSimulator.xcodeproj
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Добавить комнату | `Sources/Shared/Rooms/NewRoom/` | Создать `NewRoom.swift` с `enum` и `make()` |
| Добавить предмет | `Sources/Shared/Rooms/*/NewItem.swift` | Один файл = один предмет |
| Добавить звук | `Resources/Audio/` + `WorldModels.swift` (AudioCueID) | Добавить case + файл |
| Изменить движок звука | `Sources/Shared/AudioCoordinator.swift` | 587 строк, complex |
| Изменить движок машин | `Sources/Shared/Vehicles/` | 9 файлов, GKStateMachine |
| Добавить команду | `GameViewModel+Actions.swift` | switch в `handle(command:)` |
| MCP-команды | `Sources/Shared/EmbeddedMCPServer.swift` | protocol MCPToolRuntime |

## CONVENTIONS

### КРИТИЧЕСКИ ВАЖНО
- **ОДНА ЛОГИКА, ОДИН ФАЙЛ** — каждый новый предмет/механика = отдельный .swift файл
- **Коммиты после каждого блока** — буквально каждый логический блок коммитится на GitHub
- **MCP сначала** — для игровых действий сначала пробуем `freeworld-game`, потом код

### СТРОГОЕ ПРАВИЛО: GAMEPLAYKIT
**ВСЯ логика состояний, переходов и автоматов — ТОЛЬКО через GameplayKit. Никакой ручной математики. Никаких костылей.**

- **GKStateMachine** — для любых state machine (двери, калитка, машины, соседи, NPC, позы, инвентарь, этапы игры)
- **GKState** — каждое состояние = `private final class XxxState: GKState` с `isValidNextState`
- **GKRuleSystem** — для правил и условий (если нужно)
- **GKAgent** — для агентного поведения (если нужно)
- **GKMonteCarloStrategist** — для ИИ (если нужно)
- **GKMinMaxStrategist** — для ИИ (если нужно)
- **GKDecisionTree** — для дерева решений (если нужно)
- **GKMeshGraph / GKGraph** — для навигации (если нужно)

**Запрещено:**
- Писать `if/switch` цепочки для state machine вместо GKStateMachine
- Использовать ручные `enum State` + `var currentState` вместо GKState
- Делать `Timer` или `Task.sleep` для переходов состояний вместо GKStateMachine
- Писать свою математику для переходов, когда есть GameplayKit

**Пример ПРАВИЛЬНО:**
```swift
final class DoorLifecycleMachine {
    private final class ClosedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpenState.self || stateClass == LockedState.self
        }
    }
    private let machine: GKStateMachine
    // ...
}
```

**Пример НЕПРАВИЛЬНО (ЗАПРЕЩЕНО):**
```swift
enum DoorState { case closed, open, locked }
var currentState: DoorState = .closed
func open() { currentState = .open } // НЕТ!
```

### Архитектурные паттерны
- **GKStateMachine** — используется для DoorLifecycleMachine, GateLifecycleMachine, PoseMachine, CarLifecycleMachine, NeighborEncounterMachine, GroceryStoreClerkMachine
- **enum + make()** — каждая комната/предмет определены как `enum` с `static func make() -> ItemDefinition`
- **ItemDefinition** — `id`, `name`, `shortPromptProvider`, `fullDescriptionProvider`, `actionsProvider`
- **ItemAction** — `trigger`, `title`, `resultText`, `sound`, `stateMutation`
- **WorldRuntimeState** — хранит `player`, `itemStages`, `itemPositions`, `itemRooms`

### Именование
- Комната: `enum KitchenRoom` в `KitchenRoom.swift`
- Предмет: `enum KitchenKettle` в `KitchenKettle.swift`
- ID: `"kitchen.kettle"`, `"bedroom.pillow"`, `"groceryStore.teabag"`
- Дверь: `"kitchen.door.livingRoom"`, `"hallway.door.bedroom"`
- AudioCue: `.kettleLidOpen`, `.doorCloseBedroom`

## ANTI-PATTERNS (THIS PROJECT)
- **НЕЛЬЗЯ** объединять несколько предметов в один файл
- **НЕЛЬЗЯ** начинать с обзора проекта, если просят игровые действия
- **НЕЛЬЗЯ** использовать `afade` на коротких звуках (< 0.2с) — убивает сигнал
- **НЕЛЬЗЯ** коммитить без явного запроса пользователя
- **НЕЛЬЗЯ** писать state machine без GameplayKit — ТОЛЬКО GKStateMachine/GKState
- **НЕЛЬЗЯ** использовать ручные enum + var currentState для переходов состояний

## COMMANDS
```bash
# Сборка macOS
xcodebuild -scheme FreeWorldMac -destination 'platform=macOS' build

# Запуск
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'FreeWorldMac.app' -path '*/Debug/*' | head -1)"

# Сборка iOS
xcodebuild -scheme FreeWorldiOS -destination 'platform=iOS Simulator' build
```

## NOTES
- `AudioCoordinator.resourceURL` ищет: `Bundle.main/Audio` → `Bundle.main` → `Resources/Audio/` (fallback)
- `StreetTrafficCoordinator` — самый большой файл (1660 строк), содержит логику машин
- Проект не использует CocoaPods/SPM — только Xcode
- `Sources/Playtests/` — пустая папка, нет тестов

---

# MCP ИГРОВЫЕ ДЕЙСТВИЯ

Для задач про прохождение, проверку сценария, игровые действия и "поиграй" сначала используй MCP `freeworld-game`.

Порядок работы по умолчанию:
1. Сначала попробуй живые действия через MCP.
2. Смотри код только если MCP не отвечает, нужной команды нет или поведение мира надо объяснить.
3. Если пользователь просит цепочку действий, проходи её по шагам и сообщай, на каком шаге реально упёрся.

Не начинай с обзора проекта, если пользователь просит не анализ кода, а выполнение действий в мире.
