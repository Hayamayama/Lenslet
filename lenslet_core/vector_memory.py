from __future__ import annotations

from pathlib import Path
from typing import Any

import chromadb

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CHROMA_PATH = PROJECT_ROOT / "chroma_db"
COLLECTION_NAME = "lenslet_memories"
DOCUMENT_PREVIEW_CHARS = 500

client = chromadb.PersistentClient(path=str(CHROMA_PATH))
collection = client.get_or_create_collection(name=COLLECTION_NAME)



def _compose_document(text: str, summary: str) -> str:
    text = text or ""
    summary = summary or ""
    return f"{summary.strip()}\n\n{text.strip()}".strip()


def _clean_metadata(metadata: dict[str, Any]) -> dict[str, str | int | float | bool]:
    """Return Chroma-safe metadata values.

    Chroma metadata values must be scalar. Dropping None values keeps optional
    fields from crashing ingestion while preserving the useful source context.
    """
    cleaned: dict[str, str | int | float | bool] = {}

    for key, value in metadata.items():
        if value is None:
            continue
        if isinstance(value, (str, int, float, bool)):
            cleaned[str(key)] = value
        else:
            cleaned[str(key)] = str(value)

    return cleaned



def add_memory(memory_id: str, text: str, summary: str, path: str | Path) -> None:
    """Insert or update one memory in Chroma.

    `upsert` is intentional here: during development it is common to rerun the
    same capture or reuse the same memory id. `add` would fail on duplicate ids.
    """
    document = _compose_document(text=text, summary=summary)
    if not document:
        raise ValueError("Cannot add empty memory document to vector store.")

    collection.upsert(
        ids=[str(memory_id)],
        documents=[document],
        metadatas=[
            {
                "path": str(path),
                "summary": summary or "",
            }
        ],
    )


def add_document_chunk(
    chunk_id: str,
    text: str,
    metadata: dict[str, Any],
) -> None:
    """Insert or update one document chunk in Chroma.

    This is the generic memory entry point for PDF, DOCX, Markdown, browser,
    clipboard, and future ingestion sources. Source-specific modules should
    prepare text and metadata, then hand the final chunk to this function.
    """
    document = (text or "").strip()
    if not document:
        raise ValueError("Cannot add empty document chunk to vector store.")

    safe_metadata = _clean_metadata(
        {
            "source_type": "document",
            **(metadata or {}),
        }
    )

    collection.upsert(
        ids=[str(chunk_id)],
        documents=[document],
        metadatas=[safe_metadata],
    )


def search_related(query: str, n_results: int = 3) -> list[dict[str, Any]]:
    if not query or not query.strip():
        return []

    safe_n_results = max(1, int(n_results))

    try:
        results = collection.query(
            query_texts=[query],
            n_results=safe_n_results,
        )
    except Exception:
        # If Chroma is empty, corrupted, or unavailable, retrieval should not
        # prevent the capture pipeline from producing a summary and memory file.
        return []

    ids = results.get("ids", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]
    distances = results.get("distances", [[]])[0]
    documents = results.get("documents", [[]])[0]

    related: list[dict[str, Any]] = []

    for memory_id, metadata, distance, document in zip(
        ids,
        metadatas,
        distances,
        documents,
        strict=False,
    ):
        metadata = metadata or {}
        document = document or ""

        related.append(
            {
                "id": memory_id,
                "path": metadata.get("path", ""),
                "source_type": metadata.get("source_type", "screenshot"),
                "filename": metadata.get("filename", ""),
                "page": metadata.get("page"),
                "chunk_index": metadata.get("chunk_index"),
                "distance": distance,
                "text": document[:DOCUMENT_PREVIEW_CHARS],
                "metadata": metadata,
            }
        )

    return related