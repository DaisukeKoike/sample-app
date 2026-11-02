import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import handle  # noqa: E402


def test_health() -> None:
    assert handle("/health") == (200, {"status": "ok"})


def test_not_found() -> None:
    assert handle("/nope")[0] == 404
