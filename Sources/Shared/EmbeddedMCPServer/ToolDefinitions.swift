import Foundation

extension StdioMCPServer {
    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "launch_live_game",
            "description": "Открывает обычную игру со звуком и готовит ее к живому управлению.",
            "inputSchema": [
                "type": "object",
                "properties": [:]
            ]
        ],
        [
            "name": "continue_game",
            "description": "Подключается к уже идущей живой игре и продолжает с текущего места без нового старта.",
            "inputSchema": [
                "type": "object",
                "properties": [:]
            ]
        ],
        [
            "name": "start_game",
            "description": "Запускает новую игру и создает персонажа в обычной живой игре со звуком.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Имя персонажа. По умолчанию Тестер."
                    ],
                    "kind": [
                        "type": "string",
                        "description": "man или woman. По умолчанию man."
                    ]
                ]
            ]
        ],
        [
            "name": "press",
            "description": "Нажимает игровую команду: forward/backward/left/right/action/force/throw/describe/place.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "Команда управления."
                    ]
                ],
                "required": ["command"]
            ]
        ],
        [
            "name": "key_down",
            "description": "Зажимает игровую команду. Нужно для машины: держать газ, тормоз или руль.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "Команда управления."
                    ]
                ],
                "required": ["command"]
            ]
        ],
        [
            "name": "key_up",
            "description": "Отпускает ранее зажатую игровую команду.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "Команда управления."
                    ]
                ],
                "required": ["command"]
            ]
        ],
        [
            "name": "hold_key",
            "description": "Зажимает команду на указанное время и потом отпускает. Удобно для машинных прогонов через MCP.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "Команда управления."
                    ],
                    "duration": [
                        "type": "number",
                        "description": "Сколько секунд держать кнопку."
                    ]
                ],
                "required": ["command", "duration"]
            ]
        ],
        [
            "name": "get_state",
            "description": "Возвращает текущее состояние игры: комната, что рядом, статус и позиция.",
            "inputSchema": [
                "type": "object",
                "properties": [:]
            ]
        ],
        [
            "name": "observe_game",
            "description": "Тихо наблюдает за живой игрой и возвращает только новые фразы и новые события с прошлого запроса, плюс текущее состояние.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "phraseCursor": [
                        "type": "integer",
                        "description": "Сколько фраз уже было прочитано наблюдателем."
                    ],
                    "gameLogCursor": [
                        "type": "integer",
                        "description": "Сколько игровых строк лога уже было прочитано."
                    ],
                    "bridgeLogCursor": [
                        "type": "integer",
                        "description": "Сколько служебных строк моста уже было прочитано."
                    ]
                ]
            ]
        ],
        [
            "name": "get_phrases",
            "description": "Возвращает последние озвученные фразы из текущей игры.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Сколько последних фраз вернуть. По умолчанию 20."
                    ]
                ]
            ]
        ],
        [
            "name": "get_log",
            "description": "Возвращает подробный лог действий сервера или живой игры.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Сколько строк вернуть. По умолчанию 200."
                    ]
                ]
            ]
        ],
        [
            "name": "list_debug_scenarios",
            "description": "Показывает готовые отладочные сцены и точки для быстрой проверки механик.",
            "inputSchema": [
                "type": "object",
                "properties": [:]
            ]
        ],
        [
            "name": "run_debug_scenario",
            "description": "Запускает готовую отладочную сцену, например припаркованную машину, кровать или холодильник.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Имя или id отладочного сценария."
                    ],
                    "id": [
                        "type": "string",
                        "description": "Id отладочного сценария. Можно передавать вместо name."
                    ]
                ],
                "required": []
            ]
        ],
        [
            "name": "teleport",
            "description": "Мгновенно переносит игрока в нужную комнату и точку для ручной проверки механики.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "roomID": [
                        "type": "string",
                        "description": "Комната: hallway, bedroom, livingRoom, kitchen, bathroom, street."
                    ],
                    "x": [
                        "type": "integer",
                        "description": "Координата по ширине."
                    ],
                    "y": [
                        "type": "integer",
                        "description": "Координата по высоте."
                    ]
                ],
                "required": ["roomID", "x", "y"]
            ]
        ],
        [
            "name": "debug_world",
            "description": "Низкоуровневое управление миром. Операции: get_runtime_state, set_player, set_held_item, clear_held_item, set_item_location, clear_item_location, set_state, clear_state, neighbor_set_state, neighbor_loud_step, neighbor_start_break_in, neighbor_attack, neighbor_set_config, refresh.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "operation": [
                        "type": "string",
                        "description": "Имя низкоуровневой debug-операции."
                    ],
                    "itemID": [
                        "type": "string",
                        "description": "ID предмета для операций над предметами."
                    ],
                    "roomID": [
                        "type": "string",
                        "description": "Комната для игрока или предмета."
                    ],
                    "x": [
                        "type": "integer",
                        "description": "Координата X."
                    ],
                    "y": [
                        "type": "integer",
                        "description": "Координата Y."
                    ],
                    "pose": [
                        "type": "string",
                        "description": "Поза игрока: standing, lying, crawling."
                    ],
                    "name": [
                        "type": "string",
                        "description": "Имя предмета в руках."
                    ],
                    "key": [
                        "type": "string",
                        "description": "Сырой ключ состояния."
                    ],
                    "target": [
                        "type": "string",
                        "description": "Удобное имя состояния, например kettle.water, kettle.lid, kettle.placement, mug.fill, stove.stage, tv.stage."
                    ],
                    "value": [
                        "type": "string",
                        "description": "Новое строковое значение состояния."
                    ],
                    "state": [
                        "type": "string",
                        "description": "Состояние соседа: calm, warned, doorbell, breakin, resolved."
                    ],
                    "introText": [
                        "type": "string",
                        "description": "Текст старта штурма соседа."
                    ],
                    "finalText": [
                        "type": "string",
                        "description": "Текст состояния штурма."
                    ],
                    "text": [
                        "type": "string",
                        "description": "Текст для прямой соседской атаки."
                    ],
                    "logLine": [
                        "type": "string",
                        "description": "Строка в лог для соседской атаки."
                    ],
                    "responsePauseMin": [
                        "type": "number",
                        "description": "Минимальная пауза между звонками/стуками соседа."
                    ],
                    "responsePauseMax": [
                        "type": "number",
                        "description": "Максимальная пауза между звонками/стуками соседа."
                    ],
                    "breakInPauseMin": [
                        "type": "number",
                        "description": "Минимальная пауза между ударами при штурме."
                    ],
                    "breakInPauseMax": [
                        "type": "number",
                        "description": "Максимальная пауза между ударами при штурме."
                    ],
                    "hitsTarget": [
                        "type": "integer",
                        "description": "Сколько ударов нужно до пролома."
                    ],
                    "footstepCount": [
                        "type": "integer",
                        "description": "Сколько шагов делает сосед после пролома."
                    ],
                    "footstepPause": [
                        "type": "number",
                        "description": "Пауза между шагами соседа."
                    ],
                    "reset": [
                        "type": "boolean",
                        "description": "Сбросить debug-настройки соседей."
                    ]
                ],
                "required": ["operation"]
            ]
        ]
    ]
}
