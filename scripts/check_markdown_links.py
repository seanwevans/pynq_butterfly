#!/usr/bin/env python3
"""Check repository-local targets in Markdown inline links and images."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"!?\[[^\]]*\]\((?P<target>[^\s)>]+)(?:\s+[^)]*)?\)")
EXTERNAL = ("http://", "https://", "mailto:", "data:")


def main() -> int:
    failures: list[str] = []
    for document in sorted(ROOT.rglob("*.md")):
        if ".git" in document.parts:
            continue
        for line_number, line in enumerate(document.read_text(encoding="utf-8").splitlines(), 1):
            for match in LINK.finditer(line):
                raw = match.group("target")
                if raw.startswith(("#", *EXTERNAL)):
                    continue
                path = unquote(raw.split("#", 1)[0])
                if path and not (document.parent / path).resolve().exists():
                    relative = document.relative_to(ROOT)
                    failures.append(f"{relative}:{line_number}: missing {raw}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("All repository-local Markdown links resolve.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
