from __future__ import annotations

from pathlib import Path
from typing import Any

from lenslet_core.capture import capture_screen
from lenslet_core.ocr import extract_text
from lenslet_core.llm import summarize
from lenslet_core.memory import save_memory
from lenslet_core.vector_memory import add_memory, search_related


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

    if image_path is None:
        image_path = capture_screen()
    else:
        image_path = Path(image_path)
    ocr_text = extract_text(image_path)
    summary = summarize(ocr_text)

    related = search_related(summary, n_results=3)

    memory_path = save_memory(
        ocr_text=ocr_text,
        summary=summary,
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
        "memory_path": str(memory_path),
        "related": related,
    }
