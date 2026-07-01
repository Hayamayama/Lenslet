"""Lenslet user settings — shared between Python core and macOS app."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

SETTINGS_PATH = Path.home() / ".lenslet" / "settings.json"

DEFAULTS: dict[str, Any] = {
    "model_backend": "ollama",
    "ollama_model": "qwen3:8b",
    "claude_model": "claude-haiku-4-5-20251001",
    "claude_api_key": "",
    "vision_enabled": False,
    "vision_ollama_model": "qwen2.5vl:7b",
}


def load() -> dict[str, Any]:
    if not SETTINGS_PATH.exists():
        return dict(DEFAULTS)
    try:
        data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
        return {**DEFAULTS, **data}
    except Exception:
        return dict(DEFAULTS)


def get(key: str, default: Any = None) -> Any:
    return load().get(key, DEFAULTS.get(key, default))


def save(updates: dict[str, Any]) -> None:
    current = load()
    current.update(updates)
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS_PATH.write_text(
        json.dumps(current, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
