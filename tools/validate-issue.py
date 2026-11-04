"""Validate issue structure, not factual accuracy."""
import re
import sys
from pathlib import Path

REQUIRED = ["概要・背景", "再現手順・現状", "調査結果", "スコープ・対象外", "受入基準", "影響範囲", "テスト計画", "リスク・切戻し", "関連課題・依存", "完了の定義", "設計図"]

def validate(text: str) -> list[str]:
    errors = [f"missing section: {s}" for s in REQUIRED if f"## {s}" not in text]
    ids = re.findall(r"^- \[ \] (AC-\d+): (.+)$", text, re.M)
    if len(ids) < 2:
        errors.append("at least two measurable acceptance criteria required")
    if len({i for i, _ in ids}) != len(ids):
        errors.append("duplicate AC id")
    if any(len(body.strip()) < 15 for _, body in ids):
        errors.append("acceptance criterion too short")
    prose = re.sub(r"```.*?```", "", text, flags=re.S)
    if re.search(r"<[^>]+>|TODO|TBD", prose):
        errors.append("unresolved placeholder")
    if "```mermaid" not in text and not re.search(r"## 設計図\s*\n\s*図: 不要", text):
        errors.append("設計図: mermaid図、または「図: 不要（理由）」が必要")
    return errors

if __name__ == "__main__":
    errors = validate(Path(sys.argv[1]).read_text(encoding="utf-8"))
    print("\n".join(errors) if errors else "issue structure: OK")
    raise SystemExit(bool(errors))
