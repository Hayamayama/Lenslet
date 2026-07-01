"""Vision LLM page analysis for structured content (tables, flowcharts, diagrams).

Supports two backends:
  - Claude API  (claude-haiku / sonnet with vision input)
  - Ollama      (qwen2.5vl:7b or any multimodal model)

Falls back gracefully: if vision is disabled or unavailable, callers should
use Apple Vision OCR instead.
"""

from __future__ import annotations

import base64
import tempfile
from pathlib import Path

import fitz  # PyMuPDF

from lenslet_core.settings import get as _setting

VISION_PROMPT = """You are analysing a page from a clinical or academic PDF.
Extract ALL meaningful content from this page and represent it in clean Markdown.

Rules:
- For tables: output a proper Markdown table preserving rows, columns, and headers.
- For flowcharts / algorithms: describe the steps and decision branches as a numbered list or Mermaid diagram.
- For diagrams / figures: describe the visual content and any labelled structures concisely.
- For mixed content: extract text normally, then handle any visual structures above.
- Do NOT add commentary. Output only the extracted content.
- Write in the same language as the content on the page.
"""


def _render_page_to_png(page: fitz.Page, zoom: float = 2.0) -> Path:
    """Render a fitz page to a temporary PNG and return the path."""
    matrix = fitz.Matrix(zoom, zoom)
    pixmap = page.get_pixmap(matrix=matrix, alpha=False)
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    pixmap.save(tmp.name)
    return Path(tmp.name)


def _encode_image_b64(image_path: Path) -> str:
    return base64.standard_b64encode(image_path.read_bytes()).decode()


def analyze_page_with_claude(page: fitz.Page) -> str:
    try:
        import anthropic
    except ImportError as exc:
        raise RuntimeError("anthropic package not installed.") from exc

    api_key = _setting("claude_api_key", "")
    if not api_key:
        raise RuntimeError("Claude API key not set.")

    model = _setting("claude_model", "claude-haiku-4-5-20251001")
    image_path = _render_page_to_png(page)

    try:
        client = anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model=model,
            max_tokens=2048,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/png",
                                "data": _encode_image_b64(image_path),
                            },
                        },
                        {"type": "text", "text": VISION_PROMPT},
                    ],
                }
            ],
        )
        return message.content[0].text.strip()
    finally:
        image_path.unlink(missing_ok=True)


def analyze_page_with_ollama(page: fitz.Page) -> str:
    import requests

    model = _setting("vision_ollama_model", "qwen2.5vl:7b")
    image_path = _render_page_to_png(page)

    try:
        response = requests.post(
            "http://localhost:11434/api/generate",
            json={
                "model": model,
                "prompt": VISION_PROMPT,
                "images": [_encode_image_b64(image_path)],
                "stream": False,
            },
            timeout=180,
        )
        response.raise_for_status()
        return (response.json().get("response") or "").strip()
    except requests.exceptions.ConnectionError as exc:
        raise RuntimeError("Cannot connect to Ollama.") from exc
    finally:
        image_path.unlink(missing_ok=True)


def analyze_page(page: fitz.Page) -> str | None:
    """Analyse a page with the configured vision backend.

    Returns structured Markdown, or None if vision is disabled / unavailable.
    """
    if not _setting("vision_enabled", False):
        return None

    backend = _setting("model_backend", "ollama")

    try:
        if backend == "claude" and _setting("claude_api_key", ""):
            return analyze_page_with_claude(page)
        else:
            return analyze_page_with_ollama(page)
    except Exception:
        return None
