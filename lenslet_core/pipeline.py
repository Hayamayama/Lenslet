from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from lenslet_core.capture import capture_screen
from lenslet_core.ocr import extract_text
from lenslet_core.llm import summarize_with_tags
from lenslet_core.memory import save_memory
from lenslet_core.vector_memory import add_memory, search_related


def _error_result(message: str, image_path: Path | None = None) -> dict[str, Any]:
    return {
        "status": "error",
        "image_path": str(image_path) if image_path else None,
        "ocr": None,
        "summary": None,
        "memory_path": None,
        "related": [],
        "error": message,
    }


def run_text_pipeline(text: str) -> dict[str, Any]:
    """Run the pipeline with raw text (e.g. clipboard), skipping OCR."""
    if not text or not text.strip():
        return _error_result("Input text is empty.")

    source_app = os.environ.get("LENSLET_SOURCE_APP", "")
    source_url = os.environ.get("LENSLET_SOURCE_URL", "")

    try:
        summary, tags = summarize_with_tags(text)
        related = search_related(summary, n_results=3)
        memory_path = save_memory(
            ocr_text=text, summary=summary, tags=tags, source="clipboard",
            source_app=source_app, source_url=source_url,
        )
        memory_id = memory_path.stem
        add_memory(memory_id=memory_id, text=text, summary=summary, path=memory_path)

        return {
            "status": "success",
            "image_path": None,
            "ocr": text,
            "summary": summary,
            "tags": tags,
            "memory_path": str(memory_path),
            "related": related,
            "error": None,
        }
    except Exception as exc:
        return _error_result(str(exc))


def run_capture_pipeline(
    image_path: str | Path | None = None,
) -> dict[str, Any]:
    """
    Run the full Lenslet capture pipeline once.

    Flow:
    1. Use provided image path, or fall back to interactive macOS screenshot selection
    2. Apple Vision OCR
    3. Local LLM summary
    4. Related memory search
    5. Markdown memory save
    6. Vector memory insert

    Returns a JSON-serializable dictionary for Swift / CLI callers.
    """

    source_app = os.environ.get("LENSLET_SOURCE_APP", "")
    source_url = os.environ.get("LENSLET_SOURCE_URL", "")

    if image_path is None:
        image_path = capture_screen()
    else:
        image_path = Path(image_path)
    if not image_path.exists():
        return _error_result(f"Image not found: {image_path}", image_path)
    ocr_text = extract_text(image_path)
    if not ocr_text or not ocr_text.strip():
        return _error_result("OCR produced no text.", image_path)

    try:
        summary, tags = summarize_with_tags(ocr_text)

        related = search_related(summary, n_results=3)

        memory_path = save_memory(
            ocr_text=ocr_text,
            summary=summary,
            tags=tags,
            source="screen_capture",
            source_app=source_app,
            source_url=source_url,
        )

        memory_id = memory_path.stem

        add_memory(
            memory_id=memory_id,
            text=ocr_text,
            summary=summary,
            path=memory_path,
        )

        return {
            "status": "success",
            "image_path": str(Path(image_path)),
            "ocr": ocr_text,
            "summary": summary,
            "tags": tags,
            "memory_path": str(memory_path),
            "related": related,
            "error": None,
        }
    except Exception as exc:
        return {
            "status": "error",
            "image_path": str(image_path),
            "ocr": ocr_text,
            "summary": None,
            "memory_path": None,
            "related": [],
            "error": str(exc),
        }
