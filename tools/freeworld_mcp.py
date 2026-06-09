#!/usr/bin/env python3
import argparse
import json
import os
import socket
import subprocess
import sys
import time


SERVER_NAME = "freeworld-mcp"
SERVER_VERSION = "2.1.0"
DEFAULT_PROTOCOL_VERSION = "2025-03-26"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 47831


TOOLS = [
    {
        "name": "launch_live_game",
        "description": "Открывает обычную игру со звуком и готовит ее к живому управлению.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "continue_game",
        "description": "Подключается к уже идущей живой игре и продолжает с текущего места без нового старта.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "start_game",
        "description": "Запускает новую игру и создает персонажа в обычной живой игре со звуком.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Имя персонажа. По умолчанию Тестер."},
                "kind": {"type": "string", "description": "man или woman. По умолчанию man."},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "press",
        "description": "Нажимает игровую команду: forward/backward/left/right/action/force/throw/describe/place.",
        "inputSchema": {
            "type": "object",
            "properties": {"command": {"type": "string", "description": "Команда управления."}},
            "required": ["command"],
            "additionalProperties": False,
        },
    },
    {
        "name": "key_down",
        "description": "Зажимает игровую команду. Нужно для машины: держать газ, тормоз или руль.",
        "inputSchema": {
            "type": "object",
            "properties": {"command": {"type": "string", "description": "Команда управления."}},
            "required": ["command"],
            "additionalProperties": False,
        },
    },
    {
        "name": "key_up",
        "description": "Отпускает ранее зажатую игровую команду.",
        "inputSchema": {
            "type": "object",
            "properties": {"command": {"type": "string", "description": "Команда управления."}},
            "required": ["command"],
            "additionalProperties": False,
        },
    },
    {
        "name": "hold_key",
        "description": "Зажимает команду на указанное время и потом отпускает. Удобно для машинных прогонов через MCP.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Команда управления."},
                "duration": {"type": "number", "description": "Сколько секунд держать кнопку."},
            },
            "required": ["command", "duration"],
            "additionalProperties": False,
        },
    },
    {
        "name": "get_state",
        "description": "Возвращает текущее состояние игры: комната, что рядом, статус и позиция.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "observe_game",
        "description": "Тихо наблюдает за живой игрой и возвращает только новые фразы и новые события с прошлого запроса, плюс текущее состояние.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "phraseCursor": {"type": "integer", "description": "Сколько фраз уже было прочитано наблюдателем."},
                "gameLogCursor": {"type": "integer", "description": "Сколько игровых строк лога уже было прочитано."},
                "bridgeLogCursor": {"type": "integer", "description": "Сколько служебных строк моста уже было прочитано."},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "get_phrases",
        "description": "Возвращает последние озвученные фразы из текущей игры.",
        "inputSchema": {
            "type": "object",
            "properties": {"limit": {"type": "integer", "description": "Сколько последних фраз вернуть. По умолчанию 20."}},
            "additionalProperties": False,
        },
    },
    {
        "name": "get_log",
        "description": "Возвращает подробный лог действий сервера или живой игры.",
        "inputSchema": {
            "type": "object",
            "properties": {"limit": {"type": "integer", "description": "Сколько строк вернуть. По умолчанию 200."}},
            "additionalProperties": False,
        },
    },
    {
        "name": "list_debug_scenarios",
        "description": "Показывает готовые отладочные сцены и точки для быстрой проверки механик.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "run_debug_scenario",
        "description": "Запускает готовую отладочную сцену, например припаркованную машину, кровать или холодильник.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Имя или id отладочного сценария."},
                "id": {"type": "string", "description": "Id отладочного сценария. Можно передавать вместо name."},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "teleport",
        "description": "Мгновенно переносит игрока в нужную комнату и точку для ручной проверки механики.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "roomID": {"type": "string", "description": "Комната: hallway, bedroom, livingRoom, kitchen, bathroom, street."},
                "x": {"type": "integer", "description": "Координата по ширине."},
                "y": {"type": "integer", "description": "Координата по высоте."},
            },
            "required": ["roomID", "x", "y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "debug_world",
        "description": "Низкоуровневое управление миром. Операции: get_runtime_state, set_player, set_held_item, clear_held_item, set_item_location, clear_item_location, set_state, clear_state, neighbor_set_state, neighbor_loud_step, neighbor_start_break_in, neighbor_attack, neighbor_set_config, refresh.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "operation": {"type": "string", "description": "Имя низкоуровневой debug-операции."},
                "itemID": {"type": "string", "description": "ID предмета для операций над предметами."},
                "roomID": {"type": "string", "description": "Комната для игрока или предмета."},
                "x": {"type": "integer", "description": "Координата X."},
                "y": {"type": "integer", "description": "Координата Y."},
                "pose": {"type": "string", "description": "Поза игрока: standing, lying, crawling."},
                "name": {"type": "string", "description": "Имя предмета в руках."},
                "key": {"type": "string", "description": "Сырой ключ состояния."},
                "target": {"type": "string", "description": "Удобное имя состояния, например kettle.water, kettle.lid, kettle.placement, mug.fill, stove.stage, tv.stage."},
                "value": {"type": "string", "description": "Новое строковое значение состояния."},
                "state": {"type": "string", "description": "Состояние соседа: calm, warned, doorbell, breakin, resolved."},
                "introText": {"type": "string", "description": "Текст старта штурма соседа."},
                "finalText": {"type": "string", "description": "Текст состояния штурма."},
                "text": {"type": "string", "description": "Текст для прямой соседской атаки."},
                "logLine": {"type": "string", "description": "Строка в лог для соседской атаки."},
                "responsePauseMin": {"type": "number", "description": "Минимальная пауза между звонками/стуками соседа."},
                "responsePauseMax": {"type": "number", "description": "Максимальная пауза между звонками/стуками соседа."},
                "breakInPauseMin": {"type": "number", "description": "Минимальная пауза между ударами при штурме."},
                "breakInPauseMax": {"type": "number", "description": "Максимальная пауза между ударами при штурме."},
                "hitsTarget": {"type": "integer", "description": "Сколько ударов нужно до пролома."},
                "footstepCount": {"type": "integer", "description": "Сколько шагов делает сосед после пролома."},
                "footstepPause": {"type": "number", "description": "Пауза между шагами соседа."},
                "reset": {"type": "boolean", "description": "Сбросить debug-настройки соседей."},
            },
            "required": ["operation"],
            "additionalProperties": False,
        },
    },
]


def build_text_result(data, is_error=False):
    text = json.dumps(data, ensure_ascii=False, indent=2)
    result = {"content": [{"type": "text", "text": text}], "isError": bool(is_error)}
    if not is_error:
        result["structuredContent"] = data
    return result


class LiveBridge:
    def __init__(self):
        env = os.environ
        self.host = env.get("FREEWORLD_LIVE_HOST", DEFAULT_HOST)
        self.port = int(env.get("FREEWORLD_LIVE_PORT", str(DEFAULT_PORT)))
        self.app_path = env.get("FREEWORLD_LIVE_APP_PATH", "")
        self._has_active_session = False

    def ping(self, timeout=0.5):
        try:
            payload = self.request("ping", {}, timeout=timeout)
            return bool(payload.get("ok"))
        except Exception:
            return False

    def ensure_live_game_available(self):
        if self.ping():
            return
        if not self.app_path:
            raise RuntimeError("Не найден путь к обычной игре. Нужен FREEWORLD_LIVE_APP_PATH.")
        if not os.path.exists(self.app_path):
            raise RuntimeError(f"Не нашел собранное приложение игры по пути {self.app_path}.")
        subprocess.run(["/usr/bin/open", self.app_path], check=False)
        deadline = time.time() + 10
        while time.time() < deadline:
            if self.ping():
                return
            time.sleep(0.2)
        raise RuntimeError("Обычная игра открылась, но мост управления не ответил.")

    def request(self, action, arguments, timeout=3):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            sock.connect((self.host, self.port))
            payload = json.dumps({"action": action, "arguments": arguments}, ensure_ascii=False).encode("utf-8") + b"\n"
            sock.sendall(payload)
            data = b""
            while b"\n" not in data:
                chunk = sock.recv(65536)
                if not chunk:
                    raise RuntimeError("Живая игра закрыла соединение раньше времени.")
                data += chunk
            line = data.split(b"\n", 1)[0]
            response = json.loads(line.decode("utf-8"))
            return response
        except socket.timeout:
            raise RuntimeError("Живая игра не ответила вовремя.")
        finally:
            try:
                sock.close()
            except Exception:
                pass

    def payload_from_response(self, response):
        if not response.get("ok", False):
            raise RuntimeError(str(response.get("error") or "Живая игра вернула ошибку."))
        return response.get("payload")

    def launch_live_game(self):
        self.ensure_live_game_available()
        return {"mode": "live", "message": "Обычная игра запущена и готова принимать команды."}

    def continue_game(self):
        self.ensure_live_game_available()
        payload = self.payload_from_response(self.request("get_state", {}))
        self._has_active_session = True
        return payload

    def start_game(self, name, kind):
        self.ensure_live_game_available()
        payload = self.payload_from_response(self.request("start_game", {"name": name, "kind": kind}))
        self._has_active_session = True
        return payload

    def require_session(self):
        if not self._has_active_session:
            raise RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")

    def press(self, command):
        self.require_session()
        return self.payload_from_response(self.request("press", {"command": command}))

    def key_down(self, command):
        self.require_session()
        return self.payload_from_response(self.request("key_down", {"command": command}))

    def key_up(self, command):
        self.require_session()
        return self.payload_from_response(self.request("key_up", {"command": command}))

    def hold_key(self, command, duration):
        self.require_session()
        self.key_down(command)
        time.sleep(max(0.05, min(10.0, float(duration))))
        return self.key_up(command)

    def get_state(self):
        self.require_session()
        return self.payload_from_response(self.request("get_state", {}))

    def observe_game(self, phrase_cursor, game_log_cursor, bridge_log_cursor):
        self.require_session()
        return self.payload_from_response(
            self.request(
                "observe_game",
                {
                    "phraseCursor": max(0, int(phrase_cursor)),
                    "gameLogCursor": max(0, int(game_log_cursor)),
                    "bridgeLogCursor": max(0, int(bridge_log_cursor)),
                },
            )
        )

    def get_phrases(self, limit):
        self.require_session()
        return self.payload_from_response(self.request("get_phrases", {"limit": max(1, int(limit))}))

    def get_log(self, limit):
        self.require_session()
        return self.payload_from_response(self.request("get_log", {"limit": max(1, int(limit))}))

    def list_debug_scenarios(self):
        self.ensure_live_game_available()
        return self.payload_from_response(self.request("list_debug_scenarios", {}))

    def run_debug_scenario(self, name):
        self.require_session()
        return self.payload_from_response(self.request("run_debug_scenario", {"name": name}))

    def teleport(self, room_id, x, y):
        self.require_session()
        return self.payload_from_response(self.request("teleport", {"roomID": room_id, "x": int(x), "y": int(y)}))

    def debug_world(self, arguments):
        self.require_session()
        return self.payload_from_response(self.request("debug_world", arguments))


RUNTIME = LiveBridge()


def jsonrpc_result(request_id, result):
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def jsonrpc_error(request_id, code, message):
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def handle_tool_call(name, arguments):
    arguments = arguments or {}
    if name == "launch_live_game":
        return build_text_result(RUNTIME.launch_live_game())
    if name == "continue_game":
        return build_text_result(RUNTIME.continue_game())
    if name == "start_game":
        return build_text_result(RUNTIME.start_game(str(arguments.get("name") or "Тестер"), str(arguments.get("kind") or "man")))
    if name == "press":
        return build_text_result(RUNTIME.press(str(arguments.get("command") or "")))
    if name == "key_down":
        return build_text_result(RUNTIME.key_down(str(arguments.get("command") or "")))
    if name == "key_up":
        return build_text_result(RUNTIME.key_up(str(arguments.get("command") or "")))
    if name == "hold_key":
        return build_text_result(RUNTIME.hold_key(str(arguments.get("command") or ""), float(arguments.get("duration") or 0.1)))
    if name == "get_state":
        return build_text_result(RUNTIME.get_state())
    if name == "observe_game":
        return build_text_result(
            RUNTIME.observe_game(
                arguments.get("phraseCursor") or 0,
                arguments.get("gameLogCursor") or 0,
                arguments.get("bridgeLogCursor") or 0,
            )
        )
    if name == "get_phrases":
        return build_text_result(RUNTIME.get_phrases(arguments.get("limit") or 20))
    if name == "get_log":
        return build_text_result(RUNTIME.get_log(arguments.get("limit") or 200))
    if name == "list_debug_scenarios":
        return build_text_result(RUNTIME.list_debug_scenarios())
    if name == "run_debug_scenario":
        resolved_name = str(arguments.get("name") or arguments.get("id") or "")
        if not resolved_name:
            raise RuntimeError("Для run_debug_scenario нужно поле name или id.")
        return build_text_result(RUNTIME.run_debug_scenario(resolved_name))
    if name == "teleport":
        return build_text_result(RUNTIME.teleport(arguments.get("roomID"), arguments.get("x"), arguments.get("y")))
    if name == "debug_world":
        return build_text_result(RUNTIME.debug_world(arguments))
    raise RuntimeError(f"Unknown tool: {name}")


def handle_jsonrpc(payload):
    method = payload.get("method")
    request_id = payload.get("id")
    params = payload.get("params") or {}

    if method == "initialize":
        protocol_version = str(params.get("protocolVersion") or DEFAULT_PROTOCOL_VERSION)
        result = {
            "protocolVersion": protocol_version,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        }
        return jsonrpc_result(request_id, result)

    if method == "notifications/initialized":
        return None

    if method == "ping":
        return jsonrpc_result(request_id, {})

    if method == "tools/list":
        return jsonrpc_result(request_id, {"tools": TOOLS})

    if method == "tools/call":
        try:
            result = handle_tool_call(str(params.get("name") or ""), params.get("arguments") or {})
            return jsonrpc_result(request_id, result)
        except Exception as exc:
            return jsonrpc_result(request_id, build_text_result({"error": str(exc)}, is_error=True))

    return jsonrpc_error(request_id, -32601, f"Method not found: {method}")


def read_next_message(stdin, use_content_length):
    if not use_content_length:
        raw_line = stdin.readline()
        if not raw_line:
            return None
        line = raw_line.strip()
        if not line:
            return None
        return json.loads(line)

    header = b""
    while b"\r\n\r\n" not in header:
        chunk = stdin.buffer.read(1)
        if not chunk:
            return None
        header += chunk
    header_text, _sep, rest = header.partition(b"\r\n\r\n")
    content_length = 0
    for line in header_text.decode("utf-8", "ignore").split("\r\n"):
        if line.lower().startswith("content-length:"):
            content_length = int(line.split(":", 1)[1].strip())
            break
    body = rest
    while len(body) < content_length:
        chunk = stdin.buffer.read(content_length - len(body))
        if not chunk:
            break
        body += chunk
    return json.loads(body.decode("utf-8"))


def write_message(stdout, response, use_content_length):
    if response is None:
        return
    data = json.dumps(response, ensure_ascii=False).encode("utf-8")
    if use_content_length:
        stdout.buffer.write(f"Content-Length: {len(data)}\r\n\r\n".encode("utf-8"))
        stdout.buffer.write(data)
        stdout.flush()
    else:
        stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        stdout.flush()


def serve_stdio(use_content_length):
    while True:
        try:
            payload = read_next_message(sys.stdin, use_content_length)
        except Exception as exc:
            response = jsonrpc_error(None, -32700, f"Invalid JSON: {exc}")
            write_message(sys.stdout, response, use_content_length)
            continue
        if payload is None:
            return
        response = handle_jsonrpc(payload)
        write_message(sys.stdout, response, use_content_length)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--transport", choices=["stdio"], default="stdio")
    parser.add_argument("--line-json", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    serve_stdio(use_content_length=not args.line_json)


if __name__ == "__main__":
    main()
