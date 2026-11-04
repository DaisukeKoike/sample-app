"""SQLite persistence, transactions and deterministic synthetic fixtures."""

import sqlite3
from pathlib import Path


def connect(path: str) -> sqlite3.Connection:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript("""
    CREATE TABLE IF NOT EXISTS projects(id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS tasks(
      id INTEGER PRIMARY KEY, project_id INTEGER NOT NULL REFERENCES projects(id),
      title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'todo',
      priority INTEGER NOT NULL DEFAULT 2, due TEXT NOT NULL,
      estimate INTEGER NOT NULL, actual INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1);
    CREATE TABLE IF NOT EXISTS comments(id INTEGER PRIMARY KEY,
      task_id INTEGER NOT NULL REFERENCES tasks(id), body TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY,
      task_id INTEGER NOT NULL, action TEXT NOT NULL);
    """)
    if not db.execute("SELECT 1 FROM projects").fetchone():
        with db:
            db.executemany(
                "INSERT INTO projects VALUES (?,?)",
                [(1, "Web renewal"), (2, "Cloud migration"), (3, "Event portal")],
            )
            db.executemany(
                "INSERT INTO tasks(id,project_id,title,status,priority,due,estimate,actual) VALUES (?,?,?,?,?,?,?,?)",
                [
                    (
                        i,
                        (i - 1) % 3 + 1,
                        f"Sample task {i:02d}",
                        ["todo", "doing", "done"][i % 3],
                        i % 3 + 1,
                        f"2026-11-{i % 28 + 1:02d}",
                        i % 8 + 1,
                        i % 5,
                    )
                    for i in range(1, 37)
                ],
            )
    return db
