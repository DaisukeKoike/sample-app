"""Business rules. Training defects are isolated from infrastructure and security."""

import csv
import io
import os

BUGS = os.getenv("TRAINING_BUGS", "on") == "on"
TRANSITIONS = {"todo": {"doing"}, "doing": {"todo", "done"}, "done": {"doing"}}


class DomainError(Exception):
    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.status = status


def list_tasks(db, query: dict) -> dict:
    rows = [dict(r) for r in db.execute("SELECT * FROM tasks ORDER BY priority,id")]
    for key in ("project_id", "status"):
        if query.get(key):
            rows = [r for r in rows if str(r[key]) == str(query[key])]
    if query.get("q"):
        rows = [r for r in rows if query["q"].casefold() in r["title"].casefold()]
    if query.get("end"):
        rows = [
            r for r in rows if r["due"] < query["end"] or (not BUGS and r["due"] == query["end"])
        ]
    total = len(rows)
    page = int(query.get("page", 1))
    size = int(query.get("size", 10))
    if page < 1 or not 1 <= size <= 100:
        raise DomainError("page >= 1; size 1..100")
    offset = (page - 1) * size + (1 if BUGS and page > 1 else 0)
    return {"items": rows[offset : offset + size], "total": total, "page": page, "size": size}


def create_task(db, data: dict) -> dict:
    from datetime import date

    title = str(data.get("title", "")).strip()
    if not title or len(title) > 200:
        raise DomainError("title must contain 1..200 characters")
    due = str(data.get("due", ""))
    date.fromisoformat(due)
    estimate = int(data.get("estimate", 1))
    priority = int(data.get("priority", 2))
    if estimate < 0 or priority not in (1, 2, 3):
        raise DomainError("invalid estimate or priority")
    with db:
        cur = db.execute(
            "INSERT INTO tasks(project_id,title,due,estimate,priority) VALUES (?,?,?,?,?)",
            (int(data["project_id"]), title, due, estimate, priority),
        )
        db.execute("INSERT INTO audit(task_id,action) VALUES (?,?)", (cur.lastrowid, "created"))
    return dict(db.execute("SELECT * FROM tasks WHERE id=?", (cur.lastrowid,)).fetchone())


def update_task(db, task_id: int, data: dict) -> dict:
    with db:
        row = db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()
        if row is None:
            raise DomainError("not found", 404)
        if int(data.get("version", -1)) != row["version"]:
            raise DomainError("version conflict", 409)
        status = data.get("status", row["status"])
        if (
            status != row["status"]
            and status not in TRANSITIONS[row["status"]]
            and not (BUGS and row["status"] == "todo" and status == "done")
        ):
            raise DomainError("invalid transition", 409)
        actual = int(data.get("actual", row["actual"]))
        if actual < 0:
            raise DomainError("actual must be nonnegative")
        changed = db.execute(
            "UPDATE tasks SET status=?,actual=?,version=version+1 WHERE id=? AND version=?",
            (status, actual, task_id, row["version"]),
        )
        if changed.rowcount != 1:
            raise DomainError("version conflict", 409)
        db.execute("INSERT INTO audit(task_id,action) VALUES (?,?)", (task_id, "updated"))
    return dict(db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone())


def dashboard(db) -> dict:
    rows = [dict(r) for r in db.execute("SELECT * FROM tasks")]
    done = sum(r["status"] == "done" for r in rows)
    denominator = len(rows) + (1 if BUGS else 0)
    return {
        "total": len(rows),
        "done": done,
        "completion": round(done / denominator * 100, 1) if denominator else 0,
        "estimate": sum(r["estimate"] for r in rows),
        "actual": sum(r["actual"] for r in rows),
    }


def export_csv(db, query: dict) -> str:
    selected = {} if BUGS else {k: v for k, v in query.items() if k not in ("page", "size")}
    rows = list_tasks(db, dict(selected, page=1, size=100))["items"]
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["id", "project_id", "title", "status", "due"])
    for r in rows:
        title = r["title"]
        if title.startswith(("=", "+", "-", "@", "\t", "\r")):
            title = "'" + title
        writer.writerow([r["id"], r["project_id"], title, r["status"], r["due"]])
    return buf.getvalue()
