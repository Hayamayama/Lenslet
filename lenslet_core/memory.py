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
    tags: list[str] | None = None,
    source: str = "screen_capture",
    source_app: str = "",
    source_url: str = "",
) -> Path:
    ocr_text = _safe_text(ocr_text)
    summary = _safe_text(summary)

    if not ocr_text and not summary:
        raise ValueError("Cannot save an empty memory.")

    now = datetime.now()
    memory_id = f"{now.strftime('%Y-%m-%d_%H-%M-%S')}_{uuid4().hex[:8]}"
    path = MEMORY_DIR / f"{memory_id}.md"

    tags_line = f"Tags: {', '.join(tags)}" if tags else "Tags:"
    app_line = f"Source App: {source_app}" if source_app else ""
    url_line = f"Source URL: {source_url}" if source_url else ""
    extra_meta = "\n".join(line for line in [app_line, url_line] if line)

    content = dedent(
        f"""
        # Lenslet Memory

        Created: {now.isoformat()}
        Source: {source}
        Memory ID: {memory_id}
        {tags_line}
        {extra_meta}

        ## Summary

        {summary or "No summary generated."}

        ## Original Capture

        {ocr_text or "No OCR text captured."}
        """
    ).strip() + "\n"

    path.write_text(content, encoding="utf-8")

    return path