import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import service
from repository import connect


@pytest.fixture
def db(tmp_path):
    connection = connect(str(tmp_path / "test.db"))
    yield connection
    connection.close()


def known_bug(identifier):
    return pytest.mark.xfail(condition=service.BUGS, reason=identifier, strict=True)


def test_seed(db):
    assert service.list_tasks(db, {})["total"] == 36


def test_filter(db):
    result = service.list_tasks(db, {"project_id": "1"})
    assert result["total"] == 12
    assert all(r["project_id"] == 1 for r in result["items"])


def test_create_and_audit(db):
    task = service.create_task(db, {"title": "new", "project_id": 1, "due": "2026-11-30"})
    assert task["version"] == 1
    assert db.execute("SELECT COUNT(*) FROM audit").fetchone()[0] == 1


def test_conflict(db):
    with pytest.raises(service.DomainError, match="version conflict"):
        service.update_task(db, 1, {"version": 0, "status": "done"})


def test_transition(db):
    row = service.update_task(db, 1, {"version": 1, "status": "done"})
    assert row["version"] == 2


def test_invalid_title(db):
    with pytest.raises(service.DomainError):
        service.create_task(db, {"title": " ", "project_id": 1, "due": "2026-11-30"})


@known_bug("BUG-01 end date inclusive")
def test_end_date(db):
    expected = db.execute("SELECT COUNT(*) FROM tasks WHERE due<=?", ("2026-11-10",)).fetchone()[0]
    assert service.list_tasks(db, {"end": "2026-11-10"})["total"] == expected


@known_bug("BUG-02 pagination gap")
def test_pagination(db):
    first = service.list_tasks(db, {"size": 10})["items"]
    second = service.list_tasks(db, {"size": 10, "page": 2})["items"]
    expected = service.list_tasks(db, {"size": 20})["items"]
    assert [r["id"] for r in first + second] == [r["id"] for r in expected]


@known_bug("BUG-03 illegal transition")
def test_no_skip(db):
    with pytest.raises(service.DomainError, match="invalid transition"):
        service.update_task(db, 3, {"version": 1, "status": "done"})


@known_bug("BUG-04 dashboard denominator")
def test_completion(db):
    assert service.dashboard(db)["completion"] == 33.3


@known_bug("BUG-05 csv filters")
def test_export_filter(db):
    rows = list(csv.DictReader(io.StringIO(service.export_csv(db, {"project_id": "1"}))))
    assert len(rows) == 12
    assert all(r["project_id"] == "1" for r in rows)


def test_empty_dashboard(db):
    with db:
        db.execute("DELETE FROM tasks")
    assert service.dashboard(db)["completion"] == 0
