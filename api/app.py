"""Local-only training application; no authentication or production deployment."""

import json
import os
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from repository import connect
from service import (
    DomainError,
    create_task,
    dashboard,
    export_csv,
    list_tasks,
    update_task,
)

BASE = Path(__file__).resolve().parent
DB_PATH = os.getenv("DB_PATH", str(BASE / "data" / "training.db"))


def handle(path: str) -> tuple[int, dict]:
    if path == "/health":
        return 200, {"status": "ok"}
    return 404, {"error": "not found"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:
        pass

    def respond(
        self, status: int, body, content_type: str = "application/json; charset=utf-8"
    ) -> None:
        data = (
            json.dumps(body, ensure_ascii=False) if isinstance(body, (dict, list)) else body
        ).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def dispatch(self, method: str) -> None:
        db = None
        try:
            url = urlsplit(self.path)
            query = {k: v[0] for k, v in parse_qs(url.query).items()}
            if method == "GET" and url.path == "/health":
                self.respond(200, {"status": "ok"})
                return
            if method == "GET" and url.path == "/":
                self.respond(
                    200,
                    (BASE / "web" / "index.html").read_text(encoding="utf-8"),
                    "text/html; charset=utf-8",
                )
                return
            db = connect(DB_PATH)
            if method == "GET" and url.path == "/api/projects":
                self.respond(200, [dict(r) for r in db.execute("SELECT * FROM projects")])
            elif method == "GET" and url.path == "/api/tasks":
                self.respond(200, list_tasks(db, query))
            elif method == "GET" and url.path == "/api/dashboard":
                self.respond(200, dashboard(db))
            elif method == "GET" and url.path == "/api/export":
                self.respond(200, export_csv(db, query), "text/csv; charset=utf-8")
            elif method in ("POST", "PATCH"):
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 65536:
                    raise DomainError("body size invalid", 413)
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise DomainError("object required")
                if method == "POST" and url.path == "/api/tasks":
                    self.respond(201, create_task(db, data))
                elif method == "PATCH" and url.path.startswith("/api/tasks/"):
                    self.respond(200, update_task(db, int(url.path.split("/")[-1]), data))
                elif method == "POST" and url.path.endswith("/comments"):
                    task_id = int(url.path.split("/")[-2])
                    body = str(data.get("body", "")).strip()
                    if not body or len(body) > 2000:
                        raise DomainError("comment length 1..2000")
                    with db:
                        db.execute(
                            "INSERT INTO comments(task_id,body) VALUES (?,?)", (task_id, body)
                        )
                    self.respond(201, {"saved": True})
                else:
                    self.respond(404, {"error": "not found"})
            elif method == "GET" and url.path.endswith("/comments"):
                task_id = int(url.path.split("/")[-2])
                self.respond(
                    200,
                    [
                        dict(r)
                        for r in db.execute(
                            "SELECT * FROM comments WHERE task_id=? ORDER BY id", (task_id,)
                        )
                    ],
                )
            else:
                self.respond(404, {"error": "not found"})
        except DomainError as exc:
            self.respond(exc.status, {"error": str(exc)})
        except (ValueError, KeyError, TypeError, sqlite3.IntegrityError):
            self.respond(400, {"error": "invalid request"})
        except (OSError, sqlite3.DatabaseError):
            self.respond(500, {"error": "internal error"})
        finally:
            if db is not None:
                db.close()

    def do_GET(self) -> None:
        self.dispatch("GET")

    def do_POST(self) -> None:
        self.dispatch("POST")

    def do_PATCH(self) -> None:
        self.dispatch("PATCH")


if __name__ == "__main__":
    ThreadingHTTPServer(
        (os.getenv("HOST", "127.0.0.1"), int(os.getenv("PORT", "8080"))), Handler
    ).serve_forever()
