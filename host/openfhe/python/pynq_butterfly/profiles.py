"""Runtime-profile loading shared by board entry points."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any


def load_profile(path: str | Path) -> dict[str, Any]:
    with Path(path).open(encoding="utf-8") as stream:
        profile = json.load(stream)
    if not isinstance(profile, dict):
        raise ValueError(f"profile is not an object: {path}")
    return profile
