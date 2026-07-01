"""Query Lenslet memory and generate grounded answers."""

from __future__ import annotations

import argparse
import json
from typing import Any

from lenslet_core.llm import answer_from_context
from lenslet_core.vector_memory import collection, search_related

DEFAULT_TOP_K = 5


def query_memory(question: str, *, top_k: int = DEFAULT_TOP_K) -> dict[str, Any]:
    """Search Lenslet memory and answer the question from retrieved chunks."""
    if not question or not question.strip():
        raise ValueError("Cannot query memory with an empty question.")
    if top_k <= 0:
        raise ValueError("top_k must be greater than 0.")

    related = search_related(question.strip(), n_results=top_k)
    if not related:
        return {
            "question": question.strip(),
            "answer": "I could not find relevant Lenslet memories for this question.",
            "sources": [],
        }

    answer = answer_from_context(question.strip(), related)

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

    result = query_memory(args.question, top_k=args.top_k)

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