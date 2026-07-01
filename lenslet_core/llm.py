from __future__ import annotations

import requests

from lenslet_core.settings import get as _setting

OLLAMA_URL = "http://localhost:11434/api/generate"
REQUEST_TIMEOUT = 120

ALLOWED_TAGS = ["學習", "生活", "興趣"]

PROMPT_TEMPLATE = """You are Lenslet, a personal knowledge assistant for clinicians and learners.

The user has just captured content from their screen, clipboard, or a document.
Respond with a JSON object containing two fields: "summary" and "tags".

Rules for summary:
- Write in plain prose. No markdown headers.
- Extract the key clinical, academic, or practical ideas.
- Do not invent information not present in the captured content.
- Keep it under 150 words.

Rules for tags:
- Choose 1 to 2 tags from this fixed list only: ["學習", "生活", "興趣"]
- 學習: anything related to medicine, physical therapy, rehabilitation, anatomy, pharmacology, clinical practice, academic study, or any professional/educational content.
- 生活: daily life, personal errands, household, food, travel, finance, relationships.
- 興趣: hobbies, sports, entertainment, games, music, art, personal projects unrelated to work.
- If unsure, prefer 學習.

Respond ONLY with valid JSON, no extra text:
{{"summary": "...", "tags": ["..."]}}

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

QA_WITH_HISTORY_PROMPT_TEMPLATE = """You are Lenslet, a personal knowledge assistant for clinicians and learners.

You are in an ongoing conversation. Use the conversation history to understand context and resolve references \
(e.g. "it", "that condition", "the protocol mentioned earlier"). \
Answer the current question using the provided memory/context chunks as your knowledge source.

Rules:
- Ground your answer in the context chunks. Do not invent information.
- If a follow-up question refers to something from earlier in the conversation, use history to resolve it.
- If the context is insufficient, say so clearly.
- Keep the answer concise but clinically useful.
- When possible, mention the source filename, page, and section.

Conversation so far:
{history}

Context chunks (retrieved for the current question):
{context}

Current question:
{question}
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
    """Summarize text. Returns summary string only (for backward compatibility)."""
    summary, _ = summarize_with_tags(text)
    return summary


def summarize_with_tags(text: str) -> tuple[str, list[str]]:
    """Summarize text and return (summary, tags) tuple.

    Parses the LLM JSON response. Falls back gracefully if JSON is malformed.
    """
    import json as _json
    import re as _re

    if not text or not text.strip():
        raise ValueError("Cannot summarize empty text.")

    raw = _generate(PROMPT_TEMPLATE.format(text=text))

    # Try direct JSON parse
    try:
        parsed = _json.loads(raw)
        summary = parsed.get("summary", "").strip()
        tags = [t for t in parsed.get("tags", []) if t in ALLOWED_TAGS]
        if summary:
            return summary, tags
    except (_json.JSONDecodeError, AttributeError):
        pass

    # Try to extract JSON from within the response (some models add prose around it)
    match = _re.search(r'\{.*\}', raw, _re.DOTALL)
    if match:
        try:
            parsed = _json.loads(match.group())
            summary = parsed.get("summary", "").strip()
            tags = [t for t in parsed.get("tags", []) if t in ALLOWED_TAGS]
            if summary:
                return summary, tags
        except (_json.JSONDecodeError, AttributeError):
            pass

    # Fallback: treat entire response as summary, no tags
    return raw.strip(), []


def answer_from_context(
    question: str,
    context_chunks: list[dict],
    history: list[dict] | None = None,
) -> str:
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

        section = chunk.get("section_heading") or metadata.get("section_heading") or ""
        source_line = f"Source {index}: {filename}"
        if page:
            source_line += f", page {page}"
        if section:
            source_line += f', section "{section}"'
        source_line += f" ({source_type})"

        formatted_chunks.append(f"{source_line}\n{text}")

    context = "\n\n---\n\n".join(formatted_chunks)

    if history:
        history_lines: list[str] = []
        for turn in history:
            role = turn.get("role", "")
            text = turn.get("text", "")
            if role == "user":
                history_lines.append(f"User: {text}")
            elif role == "assistant":
                history_lines.append(f"Lenslet: {text}")
        prompt = QA_WITH_HISTORY_PROMPT_TEMPLATE.format(
            history="\n".join(history_lines),
            context=context,
            question=question.strip(),
        )
    else:
        prompt = QA_PROMPT_TEMPLATE.format(
            question=question.strip(),
            context=context,
        )

    return _generate(prompt)
