"""Query Lenslet memory and generate grounded answers."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from lenslet_core.llm import answer_from_context
from lenslet_core.vector_memory import collection, search_related

DEFAULT_TOP_K = 5


def _build_retrieval_query(question: str, history: list[dict]) -> str:
    """Prepend recent conversation context to improve retrieval relevance.

    When a user asks a follow-up like "what about complications?", the retrieval
    query needs to know the topic from earlier turns.
    """
    if not history:
        return question
    # Use last 3 user turns as context for the retrieval query
    recent_user = [t["text"] for t in history if t.get("role") == "user"][-3:]
    context_prefix = " ".join(recent_user)
    return f"{context_prefix} {question}".strip()


def query_memory(
    question: str,
    *,
    top_k: int = DEFAULT_TOP_K,
    history: list[dict] | None = None,
) -> dict[str, Any]:
    """Search Lenslet memory and answer the question from retrieved chunks."""
    if not question or not question.strip():
        raise ValueError("Cannot query memory with an empty question.")
    if top_k <= 0:
        raise ValueError("top_k must be greater than 0.")

    history = history or []

    # Enrich the retrieval query with conversation context
    retrieval_query = _build_retrieval_query(question.strip(), history)
    related = search_related(retrieval_query, n_results=top_k)

    if not related:
        return {
            "question": question.strip(),
            "answer": "I could not find relevant Lenslet memories for this question.",
            "sources": [],
        }

    answer = answer_from_context(question.strip(), related, history=history if history else None)

    return {
        "question": question.strip(),
        "answer": answer,
        "sources": related,
    }


def list_documents() -> list[dict[str, Any]]:
    """Return imported PDF/document sources grouped from vector memory chunks."""
    try:
        results = collection.get(
            include=["metadatas"],
        )
    except Exception:
        return []

    ids = results.get("ids", []) or []
    metadatas = results.get("metadatas", []) or []

    grouped: dict[str, dict[str, Any]] = {}

    for chunk_id, metadata in zip(ids, metadatas, strict=False):
        metadata = metadata or {}
        source_type = metadata.get("source_type")

        if source_type not in {"pdf", "document"}:
            continue

        path = str(metadata.get("path") or "")
        filename = str(metadata.get("filename") or path or "Unknown document")
        document_key = path or filename

        document = grouped.setdefault(
            document_key,
            {
                "id": document_key,
                "filename": filename,
                "path": path,
                "source_type": source_type,
                "course": str(metadata.get("course") or ""),
                "chunk_count": 0,
                "pages": set(),
                "last_ingested_at": str(metadata.get("ingested_at") or ""),
                "chunk_ids": [],
            },
        )

        document["chunk_count"] += 1
        document["chunk_ids"].append(chunk_id)

        page = metadata.get("page")
        if isinstance(page, int):
            document["pages"].add(page)
        elif isinstance(page, str) and page.strip().isdigit():
            document["pages"].add(int(page.strip()))

        ingested_at = str(metadata.get("ingested_at") or "")
        if ingested_at and ingested_at > document.get("last_ingested_at", ""):
            document["last_ingested_at"] = ingested_at

    documents: list[dict[str, Any]] = []

    for document in grouped.values():
        pages = sorted(document.pop("pages"))
        document["pages"] = pages
        document["page_count"] = len(pages)
        documents.append(document)

    documents.sort(
        key=lambda item: (
            item.get("last_ingested_at") or "",
            item.get("filename") or "",
        ),
        reverse=True,
    )

    return documents


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Ask a question against Lenslet memory.")
    parser.add_argument("question", nargs="?", help="Question to ask Lenslet memory.")
    parser.add_argument("--top-k", type=int, default=DEFAULT_TOP_K)
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON output.")
    parser.add_argument("--documents", action="store_true", help="List imported documents instead of asking a question.")
    parser.add_argument(
        "--history-file",
        type=str,
        default=None,
        help="Path to a JSON file containing conversation history [{role, text}, ...].",
    )
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    if args.documents:
        documents = list_documents()
        if args.json:
            print(json.dumps({"documents": documents}, ensure_ascii=False, indent=2))
        else:
            if not documents:
                print("No imported documents found.")
            for document in documents:
                print(
                    f"{document['filename']} | chunks={document['chunk_count']} | pages={document['page_count']}"
                )
        return 0

    if not args.question:
        parser.error("question is required unless --documents is used")

    history: list[dict] = []
    if args.history_file:
        try:
            history = json.loads(Path(args.history_file).read_text(encoding="utf-8"))
        except Exception:
            history = []

    result = query_memory(args.question, top_k=args.top_k, history=history)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    print(result["answer"])
    print("\nSources:")
    for index, source in enumerate(result["sources"], start=1):
        filename = source.get("filename") or source.get("path") or "unknown source"
        page = source.get("page")
        chunk_index = source.get("chunk_index")
        distance = source.get("distance")

        location_parts: list[str] = []
        if page:
            location_parts.append(f"page {page}")
        if chunk_index:
            location_parts.append(f"chunk {chunk_index}")

        location = f" ({', '.join(location_parts)})" if location_parts else ""
        distance_text = f" | distance={distance:.4f}" if isinstance(distance, float) else ""
        print(f"{index}. {filename}{location}{distance_text}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())