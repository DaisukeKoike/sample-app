"""Markdown内のmermaidブロックを簡易検査する（図種別・括弧・要素数）。完全な描画検証ではない。"""
import re
import sys
from pathlib import Path

KINDS = ("stateDiagram-v2", "stateDiagram", "sequenceDiagram", "classDiagram", "erDiagram", "flowchart", "graph")


def check(text: str) -> list[str]:
    errors = []
    blocks = re.findall(r"```mermaid\n(.*?)```", text, re.S)
    for i, b in enumerate(blocks, 1):
        lines = [x.strip() for x in b.strip().splitlines() if x.strip() and not x.strip().startswith("%%")]
        if not lines or not lines[0].startswith(KINDS):
            errors.append(f"diagram {i}: 先頭行が図の種別ではない")
            continue
        for o, c in ("()", "[]", "{}"):
            if b.count(o) != b.count(c):
                errors.append(f"diagram {i}: 括弧 {o}{c} の数が合わない")
        if len(lines) > 40:
            errors.append(f"diagram {i}: 行数が多すぎる（分割する）")
    return errors


if __name__ == "__main__":
    text = Path(sys.argv[1]).read_text(encoding="utf-8")
    errs = check(text)
    n = text.count("```mermaid")
    print("\n".join(errs) if errs else f"mermaid: OK ({n} diagrams)")
    raise SystemExit(bool(errs))
