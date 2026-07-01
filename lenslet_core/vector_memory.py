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


def _tokenize(text: str) -> list[str]:
    import re
    return re.findall(r'\b[a-z0-9]+\b', text.lower())


def search_related(query: str, n_results: int = 3) -> list[dict[str, Any]]:
    if not query or not query.strip():
        return []

    safe_n_results = max(1, int(n_results))

    # ── 1. Fetch full corpus for BM25 ──────────────────────────────────────
    try:
        corpus = collection.get(include=["documents", "metadatas"])
    except Exception:
        return []

    all_ids: list[str] = corpus.get("ids") or []
    all_docs: list[str] = corpus.get("documents") or []
    all_metas: list[dict] = corpus.get("metadatas") or []

    if not all_ids:
        return []

    # ── 2. BM25 ranking ────────────────────────────────────────────────────
    try:
        from rank_bm25 import BM25Okapi
        bm25 = BM25Okapi([_tokenize(d or "") for d in all_docs])
        bm25_scores = bm25.get_scores(_tokenize(query))
        bm25_ranking = sorted(range(len(all_ids)), key=lambda i: bm25_scores[i], reverse=True)
    except Exception:
        bm25_ranking = list(range(len(all_ids)))

    # ── 3. Vector ranking ──────────────────────────────────────────────────
    k_candidates = min(len(all_ids), max(safe_n_results * 6, 20))
    try:
        vec_results = collection.query(query_texts=[query], n_results=k_candidates)
    except Exception:
        vec_results = {"ids": [[]], "metadatas": [[]], "distances": [[]], "documents": [[]]}

    vec_ids: list[str] = vec_results.get("ids", [[]])[0]
    vec_meta: list[dict] = vec_results.get("metadatas", [[]])[0]
    vec_dist: list[float] = vec_results.get("distances", [[]])[0]
    vec_docs: list[str] = vec_results.get("documents", [[]])[0]

    # Build lookup maps from vector results
    id_to_meta = {vid: (vec_meta[i] or {}) for i, vid in enumerate(vec_ids)}
    id_to_dist = {vid: vec_dist[i] for i, vid in enumerate(vec_ids)}
    id_to_doc  = {vid: vec_docs[i] or "" for i, vid in enumerate(vec_ids)}

    # Fill gaps with corpus data for BM25-only hits
    for i, cid in enumerate(all_ids):
        if cid not in id_to_meta:
            id_to_meta[cid] = all_metas[i] or {}
        if cid not in id_to_doc:
            id_to_doc[cid] = all_docs[i] or ""
        if cid not in id_to_dist:
            id_to_dist[cid] = 1.0  # worst-case distance for BM25-only hits

    # ── 4. Reciprocal Rank Fusion ──────────────────────────────────────────
    RRF_K = 60
    rrf: dict[str, float] = {}

    for rank, idx in enumerate(bm25_ranking[:k_candidates]):
        cid = all_ids[idx]
        rrf[cid] = rrf.get(cid, 0.0) + 1.0 / (RRF_K + rank + 1)

    for rank, cid in enumerate(vec_ids):
        rrf[cid] = rrf.get(cid, 0.0) + 1.0 / (RRF_K + rank + 1)

    top_ids = sorted(rrf, key=lambda x: rrf[x], reverse=True)[:safe_n_results]

    # ── 5. Build output ────────────────────────────────────────────────────
    related: list[dict[str, Any]] = []
    for cid in top_ids:
        meta = id_to_meta.get(cid, {})
        doc  = id_to_doc.get(cid, "")
        related.append({
            "id": cid,
            "path": meta.get("path", ""),
            "source_type": meta.get("source_type", "screenshot"),
            "filename": meta.get("filename", ""),
            "page": meta.get("page"),
            "chunk_index": meta.get("chunk_index"),
            "distance": id_to_dist.get(cid, 1.0),
            "rrf_score": round(rrf[cid], 6),
            "text": doc[:DOCUMENT_PREVIEW_CHARS],
            "metadata": meta,
        })

    return related