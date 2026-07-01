from __future__ import annotations

import requests

from lenslet_core.settings import get as _setting

OLLAMA_URL = "http://localhost:11434/api/generate"
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


QA_PROMPT_TEMPLATE = """You are Lenslet.

Answer the user's question using only the provided memory/context chunks.

Rules:
- Do not invent information that is not present in the context.
- If the context is insufficient, say so clearly.
- Keep the answer concise but useful.
- When possible, mention the source filename and page number.

Question:
{question}

Context chunks:
{context}
"""


def _generate(prompt: str) -> str:
    backend = _setting("model_backend", "ollama")
    if backend == "claude":
        return _generate_claude(prompt)
    return _generate_ollama(prompt)


def _generate_ollama(prompt: str) -> str:
    model = _setting("ollama_model", "qwen3:8b")

    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": model,
                "prompt": prompt,
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


def _generate_claude(prompt: str) -> str:
    try:
        import anthropic
    except ImportError as exc:
        raise RuntimeError(
            "anthropic package not installed. Run: pip install anthropic"
        ) from exc

    api_key = _setting("claude_api_key", "")
    if not api_key:
        raise RuntimeError(
            "Claude API key is not set. Add it in Lenslet Settings."
        )

    model = _setting("claude_model", "claude-haiku-4-5-20251001")

    client = anthropic.Anthropic(api_key=api_key)
    message = client.messages.create(
        model=model,
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}],
    )
    return message.content[0].text.strip()


def summarize(text: str) -> str:
    if not text or not text.strip():
        raise ValueError("Cannot summarize empty text.")
    return _generate(PROMPT_TEMPLATE.format(text=text))


def answer_from_context(question: str, context_chunks: list[dict]) -> str:
    if not question or not question.strip():
        raise ValueError("Cannot answer an empty question.")
    if not context_chunks:
        raise ValueError("Cannot answer without context chunks.")

    formatted_chunks: list[str] = []

    for index, chunk in enumerate(context_chunks, start=1):
        metadata = chunk.get("metadata") or {}
        filename = chunk.get("filename") or metadata.get("filename") or chunk.get("path") or "unknown source"
        page = chunk.get("page") or metadata.get("page") or ""
        source_type = chunk.get("source_type") or metadata.get("source_type") or "memory"
        text = chunk.get("text") or ""

        source_line = f"Source {index}: {filename}"
        if page:
            source_line += f", page {page}"
        source_line += f" ({source_type})"

        formatted_chunks.append(f"{source_line}\n{text}")

    context = "\n\n---\n\n".join(formatted_chunks)
    prompt = QA_PROMPT_TEMPLATE.format(
        question=question.strip(),
        context=context,
    )
    return _generate(prompt)
