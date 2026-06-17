# Shared Module

Вся игровая логика в одном месте.

## STRUCTURE
```
Shared/
├── GameViewModel+*.swift  # 10 расширений (Actions, Movement, Audio, Debug, etc.)
├── AudioCoordinator.swift # Движок звука (587 строк)
├── SpeechCoordinator.swift # Озвучка текста (AVSpeechSynthesizer)
├── StreetTrafficCoordinator.swift # Уличные машины (1660 строк!)
├── EmbeddedMCPServer.swift # MCP-сервер (protocol MCPToolRuntime)
├── LiveGameBridge.swift   # Связь MCP ↔ игра
├── RootGameView.swift     # SwiftUI представление
├── Vehicles/             # Система машин (9 файлов)
├── WorldCore/            # Ядро мира (5 файлов)
└── Rooms/                # Комнаты и предметы (8 подпапок)
```

## GAMEVIEWEXTENSIONS
| Extension | Строк | Назначение |
|-----------|-------|------------|
| +Actions | 428 | Обработка команд, инвентарь, предметы |
| +World | 703 | Окружение, фокус, что рядом |
| +Movement | 444 | Ходьба по комнатам |
| +Session | 380 | Запуск, сохранение, MCP |
| +Debug | 456 | Отладочные команды |
| +NavigationBeacon | 352 | Меню быстрой навигации |
| +Neighbor | 344 | Соседи (GKStateMachine) |
| +Gate | 172 | Калитка с таймером |
| +GroceryStore | 160 | Продавец (GKStateMachine) |
| +Audio | 89 | Туториал, announce |

## KEY PATTERNS
- GameViewModel — `ObservableObject` с `@Published` свойствами
- Все state хранится в `WorldRuntimeState`
- Предметы определяются через `enum` + `static func make() -> ItemDefinition`
- Звуки через `AudioCueID` enum в `WorldModels.swift`

## ANTI-PATTERNS
- **НЕЛЬЗЯ** создавать новые GameViewModel+*.swift без необходимости
- **НЕЛЬЗЯ** дублировать логику между расширениями
- **НЕЛЬЗЯ** использовать `as any` или `@ts-ignore`
