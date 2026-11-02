"""最小のサンプル API（課題別環境の動作確認用）。実アプリに置き換えてください。"""

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


def handle(path: str) -> tuple[int, dict]:
    if path == "/health":
        return 200, {"status": "ok"}
    if path == "/":
        return 200, {"app": "sample-app", "env": os.getenv("ENV_BANNER", "local")}
    return 404, {"error": "not found"}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        status, body = handle(self.path)
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", int(os.getenv("PORT", "8080"))), Handler).serve_forever()
