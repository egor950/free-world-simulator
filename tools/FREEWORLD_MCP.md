# FreeWorld MCP

Этот MCP-сервер дает удаленное управление игрой через инструменты:

- `launch_live_game` — открыть обычную игру со звуком и подготовить ее к живому управлению.
- `continue_game` — продолжить уже идущую живую игру с того места, где остановились.
- `start_game` — запустить игру и создать персонажа в обычной живой игре.
- `press` — нажать команду игрока (`forward`, `backward`, `left`, `right`, `action`, `force`, `throw`, `describe`, `place`).
- `key_down` — зажать команду игрока. Нужно для машины: держать газ, тормоз или руль.
- `key_up` — отпустить ранее зажатую команду.
- `hold_key` — зажать команду на заданное число секунд и потом отпустить. Это основной удобный способ удалённо гнать машину через MCP.
- `get_state` — получить текущее состояние игры.
- `observe_game` — тихо наблюдать за живой игрой и получать только новые фразы и новые события с прошлого запроса.
- `get_phrases` — получить последние озвученные фразы.
- `get_log` — получить лог действий сервера и живой игры.

Тихого внутреннего режима больше нет. Если игра не открыта, сервер сам запускает обычное приложение и только потом управляет им.
Новая игра через `start_game` всегда начинает всё заново. Если нужно просто продолжить текущую сессию, используй `continue_game`.

## Запуск сервера вручную

```bash
/opt/homebrew/bin/python3 /Users/egorsitko/Desktop/проэкты/Симулятор\ свободного\ мира/tools/freeworld_mcp.py
```

Сервер работает по MCP-протоколу через `stdio`.

Для работы ему нужны переменные окружения:

```bash
FREEWORLD_ROOT_DIR="/Users/egorsitko/Desktop/проэкты/Симулятор свободного мира"
FREEWORLD_LIVE_APP_PATH="/Users/egorsitko/Library/Developer/Xcode/DerivedData/Build/Products/Debug/FreeWorldMac.app"
FREEWORLD_LIVE_HOST="127.0.0.1"
FREEWORLD_LIVE_PORT="47831"
```

## Подключение в Codex

Сервер уже добавлен командой:

```bash
codex mcp add freeworld-game \
  --env FREEWORLD_ROOT_DIR="/Users/egorsitko/Desktop/проэкты/Симулятор свободного мира" \
  --env FREEWORLD_LIVE_APP_PATH="/Users/egorsitko/Library/Developer/Xcode/DerivedData/Build/Products/Debug/FreeWorldMac.app" \
  --env FREEWORLD_LIVE_HOST="127.0.0.1" \
  --env FREEWORLD_LIVE_PORT="47831" \
  -- /opt/homebrew/bin/python3 /Users/egorsitko/Desktop/проэкты/Симулятор\ свободного\ мира/tools/freeworld_mcp.py
```

Проверка:

```bash
codex mcp get freeworld-game
```

## Подключение в LM Studio

LM Studio умеет работать с MCP-серверами, и для Free World тут используется лёгкий `stdio`-адаптер, который быстро объявляет инструменты и уже потом ходит в живую игру через локальный bridge.

Требование:

- LM Studio `0.3.17` или новее для MCP в приложении
- LM Studio `0.4.0` или новее, если MCP нужен ещё и через API

Открой в LM Studio файл `mcp.json` и добавь туда сервер `freeworld-game`.

Готовый пример лежит здесь:

- [freeworld-mcp.lmstudio.json](/Users/egorsitko/Desktop/проэкты/Симулятор%20свободного%20мира/tools/freeworld-mcp.lmstudio.json)

Смысл схемы такой:

1. LM Studio запускает `freeworld_mcp.py`.
2. `freeworld_mcp.py` сразу объявляет инструменты.
3. Когда модель реально вызывает команду, адаптер стучится в живую игру через local bridge.
4. Если игры ещё нет, адаптер запускает её только в момент настоящего действия.

Если хочешь использовать MCP из LM Studio API, в настройках сервера LM Studio надо включить:

- `Allow calling servers from mcp.json`
- `Require Authentication`

Это нужно, если к LM Studio будут обращаться внешние клиенты через API, а не только чат внутри приложения.
