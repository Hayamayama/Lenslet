from __future__ import annotations

import requests

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "qwen3:8b"
REQUEST_TIMEOUT = 120

PROMPT_TEMPLATE = """You are Lenslet.

You are helping the user understand something they have just captured from their screen.

Write a concise summary.
Extract the key ideas.
Explain important concepts if necessary.
Do not invent information that is not present.

Captured content:

{text}
"""


def summarize(text: str) -> str:
    if not text or not text.strip():
        raise ValueError("Cannot summarize empty text.")

    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": MODEL_NAME,
                "prompt": PROMPT_TEMPLATE.format(text=text),
                "stream": False,
            },
            timeout=REQUEST_TIMEOUT,
        )
    except requests.exceptions.ConnectionError as exc:
        raise RuntimeError(
            "Cannot connect to Ollama. Is `ollama serve` running?"
        ) from exc
    except requests.exceptions.Timeout as exc:
        raise RuntimeError(
            f"Ollama timed out after {REQUEST_TIMEOUT} seconds."
        ) from exc

    response.raise_for_status()

    try:
        payload = response.json()
    except ValueError as exc:
        raise RuntimeError("Ollama returned invalid JSON.") from exc

    result = payload.get("response")
    if not result:
        raise RuntimeError(f"Unexpected Ollama response: {payload}")

    return result.strip()