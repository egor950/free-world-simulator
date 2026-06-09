
import sys
import json
import subprocess

def send_command(method, params=None):
    request = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
        "id": 1
    }
    # Отправляем JSON в stdin запущенного процесса сервера
    # Здесь предполагается, что сервер уже работает в фоне или мы запускаем его сейчас
    print(f"Sending: {json.dumps(request)}")

if __name__ == "__main__":
    method = sys.argv[1]
    send_command(method)
