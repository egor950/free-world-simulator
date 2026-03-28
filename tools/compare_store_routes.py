#!/usr/bin/env python3
import argparse
import json
import os
import time
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from freeworld_mcp import LiveBridge


RUNS_DIR = Path("playtest_logs/route_runs")


def ensure_runs_dir() -> Path:
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    return RUNS_DIR


def room_id_from_state(state: dict) -> str | None:
    return state.get("room") or state.get("roomId")


def focus_from_state(state: dict) -> str | None:
    return state.get("focus") or state.get("focusId") or state.get("focusTitle")


def carrying_from_state(state: dict) -> str | None:
    return state.get("carrying")


def is_grocery_store_state(state: dict) -> bool:
    room = (room_id_from_state(state) or "").lower()
    title = (state.get("roomTitle") or "").lower()
    return room == "grocerystore" or "продуктов" in title


def phrases_confirm_store_entry(phrases: list[str]) -> bool:
    joined = " ".join(phrases).lower()
    return "ты вошел в большой продуктовый" in joined or "ты вошёл в большой продуктовый" in joined


@dataclass
class RunSummary:
    mode: str
    started_at: str
    finished_at: str
    completed: bool
    duration_sec: float
    starting_room: str | None
    final_room: str | None
    final_focus: str | None
    final_carrying: str | None
    phrase_count: int
    state_change_count: int
    unique_rooms: list[str]
    last_phrases: list[str]
    notes: str | None = None

    def as_dict(self) -> dict:
        return {
            "mode": self.mode,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "completed": self.completed,
            "duration_sec": round(self.duration_sec, 2),
            "starting_room": self.starting_room,
            "final_room": self.final_room,
            "final_focus": self.final_focus,
            "final_carrying": self.final_carrying,
            "phrase_count": self.phrase_count,
            "state_change_count": self.state_change_count,
            "unique_rooms": self.unique_rooms,
            "last_phrases": self.last_phrases,
            "notes": self.notes,
        }


def connect_live_bridge() -> LiveBridge:
    bridge = LiveBridge()
    bridge.continue_game()
    return bridge


def record_run(mode: str, timeout_sec: float, notes: str | None) -> Path:
    bridge = connect_live_bridge()
    state = bridge.get_state()

    started_at = datetime.now().astimezone().isoformat()
    watch_started_monotonic = time.monotonic()
    movement_started_at: str | None = None
    movement_started_monotonic: float | None = None

    phrase_cursor = 999999
    game_log_cursor = 999999
    bridge_log_cursor = 999999
    phrase_count = 0
    state_change_count = 0
    room_counter: Counter[str] = Counter()
    recent_phrases: list[str] = []

    starting_room = room_id_from_state(state)
    if starting_room:
        room_counter[starting_room] += 1
    has_left_store_zone = not is_grocery_store_state(state)

    print(f"Старт прогона: {mode}", flush=True)
    print(
        f"Начальная точка: room={starting_room}, focus={focus_from_state(state)}, carrying={carrying_from_state(state)}",
        flush=True,
    )
    print("Сейчас просто играй. Я сам поймаю момент входа в продуктовый.", flush=True)

    completed = False
    final_state = state

    while time.monotonic() - watch_started_monotonic <= timeout_sec:
        observed = bridge.observe_game(phrase_cursor, game_log_cursor, bridge_log_cursor)
        phrase_cursor = observed.get("phraseCursor", phrase_cursor)
        game_log_cursor = observed.get("gameLogCursor", game_log_cursor)
        bridge_log_cursor = observed.get("bridgeLogCursor", bridge_log_cursor)
        saw_activity = False

        if observed.get("stateChanged"):
            final_state = observed.get("state") or final_state
            state_change_count += 1
            room = room_id_from_state(final_state)
            if room:
                room_counter[room] += 1
            if not is_grocery_store_state(final_state):
                has_left_store_zone = True
            saw_activity = True
            print(
                "state "
                + json.dumps(
                    {
                        "room": room,
                        "focus": focus_from_state(final_state),
                        "carrying": carrying_from_state(final_state),
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )

        new_phrases = observed.get("newPhrases") or []
        if new_phrases:
            phrase_count += len(new_phrases)
            recent_phrases.extend(new_phrases)
            recent_phrases = recent_phrases[-12:]
            saw_activity = True
            print("phrases " + " | ".join(new_phrases[-2:]), flush=True)
            if has_left_store_zone and phrases_confirm_store_entry(new_phrases):
                completed = True
                break

        if saw_activity and movement_started_monotonic is None:
            movement_started_monotonic = time.monotonic()
            movement_started_at = datetime.now().astimezone().isoformat()
            print("Таймер пошёл: поймал первое движение.", flush=True)

        if has_left_store_zone and is_grocery_store_state(final_state):
            completed = True
            break

        print("без нового, смотрю дальше", flush=True)
        time.sleep(1)

    finished_at = datetime.now().astimezone().isoformat()
    effective_started_at = movement_started_at or started_at
    effective_duration_sec = (
        time.monotonic() - movement_started_monotonic
        if movement_started_monotonic is not None
        else 0.0
    )
    summary = RunSummary(
        mode=mode,
        started_at=effective_started_at,
        finished_at=finished_at,
        completed=completed,
        duration_sec=effective_duration_sec,
        starting_room=starting_room,
        final_room=room_id_from_state(final_state),
        final_focus=focus_from_state(final_state),
        final_carrying=carrying_from_state(final_state),
        phrase_count=phrase_count,
        state_change_count=state_change_count,
        unique_rooms=sorted(room_counter.keys()),
        last_phrases=recent_phrases[-8:],
        notes=notes,
    )

    ensure_runs_dir()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_path = RUNS_DIR / f"{timestamp}_{mode}.json"
    output_path.write_text(json.dumps(summary.as_dict(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if completed:
        print(f"Прогон завершён. Вошёл в продуктовый за {summary.duration_sec:.1f} сек.", flush=True)
    else:
        print(f"Прогон не завершён за {summary.duration_sec:.1f} сек.", flush=True)
    print(f"Сохранил результат: {output_path}", flush=True)
    return output_path


def latest_run(mode: str) -> Path | None:
    ensure_runs_dir()
    files = sorted(RUNS_DIR.glob(f"*_{mode}.json"))
    return files[-1] if files else None


def load_run(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def compare_runs(walk_path: Path | None, car_path: Path | None) -> int:
    walk_path = walk_path or latest_run("walk")
    car_path = car_path or latest_run("car")

    if not walk_path or not walk_path.exists():
        print("Не нашёл пеший прогон.", flush=True)
        return 1
    if not car_path or not car_path.exists():
        print("Не нашёл машинный прогон.", flush=True)
        return 1

    walk = load_run(walk_path)
    car = load_run(car_path)

    print(f"Пеший: {walk_path}", flush=True)
    print(f"Машина: {car_path}", flush=True)
    print("", flush=True)

    def line(label: str, left, right):
        print(f"{label}: пешком={left} | машина={right}", flush=True)

    line("Завершён", walk.get("completed"), car.get("completed"))
    line("Время, сек", walk.get("duration_sec"), car.get("duration_sec"))
    line("Смен состояний", walk.get("state_change_count"), car.get("state_change_count"))
    line("Фраз", walk.get("phrase_count"), car.get("phrase_count"))
    line("Комнаты", ",".join(walk.get("unique_rooms") or []), ",".join(car.get("unique_rooms") or []))
    print("", flush=True)

    if walk.get("completed") and car.get("completed"):
        walk_time = float(walk["duration_sec"])
        car_time = float(car["duration_sec"])
        if walk_time < car_time:
            print(f"Сейчас пешком быстрее на {car_time - walk_time:.1f} сек.", flush=True)
        elif car_time < walk_time:
            print(f"Сейчас машина быстрее на {walk_time - car_time:.1f} сек.", flush=True)
        else:
            print("Сейчас оба маршрута по времени почти одинаковые.", flush=True)
    elif walk.get("completed"):
        print("Сейчас пеший завершён, а машинный нет.", flush=True)
    elif car.get("completed"):
        print("Сейчас машинный завершён, а пеший нет.", flush=True)
    else:
        print("Сейчас оба прогона незавершённые, честного сравнения нет.", flush=True)

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Сохраняет и сравнивает ручные прогоны до продуктового через живую игру Free World."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    record_parser = subparsers.add_parser("record", help="Записать новый ручной прогон.")
    record_parser.add_argument("mode", choices=["walk", "car"], help="Тип прогона.")
    record_parser.add_argument("--timeout", type=float, default=300.0, help="Сколько секунд ждать завершения.")
    record_parser.add_argument("--notes", default=None, help="Короткая заметка про прогон.")

    compare_parser = subparsers.add_parser("compare", help="Сравнить последний пеший и машинный прогоны.")
    compare_parser.add_argument("--walk", type=Path, default=None, help="Явный путь к пешему прогону.")
    compare_parser.add_argument("--car", type=Path, default=None, help="Явный путь к машинному прогону.")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "record":
        record_run(args.mode, args.timeout, args.notes)
        return 0
    if args.command == "compare":
        return compare_runs(args.walk, args.car)
    parser.error("Неизвестная команда.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
