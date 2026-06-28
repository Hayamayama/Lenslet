from __future__ import annotations

from datetime import datetime
from pathlib import Path
from textwrap import dedent
from uuid import uuid4

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MEMORY_DIR = PROJECT_ROOT / "memories"

MEMORY_DIR.mkdir(parents=True, exist_ok=True)


def _safe_text(value: str | None) -> str:
    return (value or "").strip()


def save_memory(
    ocr_text: str,
    summary: str,
) -> Path:
    ocr_text = _safe_text(ocr_text)
    summary = _safe_text(summary)

    if not ocr_text and not summary:
        raise ValueError("Cannot save an empty memory.")

    now = datetime.now()
    memory_id = f"{now.strftime('%Y-%m-%d_%H-%M-%S')}_{uuid4().hex[:8]}"
    path = MEMORY_DIR / f"{memory_id}.md"

    content = dedent(
        f"""
        # Lenslet Memory

        Created: {now.isoformat()}
        Source: screen_capture
        Memory ID: {memory_id}

        ## Summary

        {summary or "No summary generated."}

        ## Original Capture

        {ocr_text or "No OCR text captured."}
        """
    ).strip() + "\n"

    path.write_text(content, encoding="utf-8")

    return path