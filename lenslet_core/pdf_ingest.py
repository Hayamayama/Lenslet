

"""PDF ingestion pipeline for Lenslet document memory.

This module turns text-based PDFs into page-aware chunks and stores them in the
shared vector memory layer. It intentionally does not handle OCR yet; scanned
PDFs should be detected and routed to a future Vision/OCR fallback.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import fitz  # PyMuPDF

from lenslet_core.vector_memory import add_document_chunk

DEFAULT_CHUNK_SIZE = 1400
DEFAULT_CHUNK_OVERLAP = 200


@dataclass(frozen=True)
class PdfChunk:
    """One searchable chunk extracted from a PDF page."""

    chunk_id: str
    text: str
    metadata: dict[str, str | int | float | bool]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _stable_pdf_id(path: Path) -> str:
    """Build a stable id from file path and modified time."""
    resolved = path.expanduser().resolve()
    stat = resolved.stat()
    raw = f"{resolved}:{stat.st_mtime_ns}:{stat.st_size}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _chunk_text(text: str, chunk_size: int, overlap: int) -> list[str]:
    """Split text into overlapping character chunks.

    Character chunking is intentionally simple for v1. It is predictable, fast,
    and good enough for lecture slides and text-based PDFs.
    """
    clean = "\n".join(line.strip() for line in text.splitlines() if line.strip())
    if not clean:
        return []

    if chunk_size <= 0:
        raise ValueError("chunk_size must be greater than 0")
    if overlap < 0:
        raise ValueError("overlap cannot be negative")
    if overlap >= chunk_size:
        raise ValueError("overlap must be smaller than chunk_size")

    chunks: list[str] = []
    start = 0

    while start < len(clean):
        end = min(start + chunk_size, len(clean))
        chunk = clean[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end == len(clean):
            break
        start = end - overlap

    return chunks


def extract_pdf_chunks(
    pdf_path: str | Path,
    *,
    course: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_CHUNK_OVERLAP,
) -> list[PdfChunk]:
    """Extract page-aware chunks from a text-based PDF."""
    path = Path(pdf_path).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"PDF not found: {path}")
    if path.suffix.lower() != ".pdf":
        raise ValueError(f"Expected a .pdf file, got: {path}")

    pdf_id = _stable_pdf_id(path)
    ingested_at = _now_iso()
    chunks: list[PdfChunk] = []

    with fitz.open(path) as document:
        for page_index, page in enumerate(document, start=1):
            page_text = page.get_text("text") or ""
            page_chunks = _chunk_text(page_text, chunk_size=chunk_size, overlap=overlap)

            for chunk_index, chunk_text in enumerate(page_chunks, start=1):
                chunk_id = f"pdf:{pdf_id}:p{page_index}:c{chunk_index}"
                metadata: dict[str, str | int | float | bool] = {
                    "source_type": "pdf",
                    "path": str(path),
                    "filename": path.name,
                    "course": course,
                    "page": page_index,
                    "chunk_index": chunk_index,
                    "pdf_id": pdf_id,
                    "ingested_at": ingested_at,
                    "needs_ocr": False,
                }
                chunks.append(PdfChunk(chunk_id=chunk_id, text=chunk_text, metadata=metadata))

    return chunks


def ingest_pdf(
    pdf_path: str | Path,
    *,
    course: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_CHUNK_OVERLAP,
) -> dict[str, int | str | bool]:
    """Extract chunks from a PDF and store them in Lenslet vector memory."""
    path = Path(pdf_path).expanduser().resolve()
    chunks = extract_pdf_chunks(
        path,
        course=course,
        chunk_size=chunk_size,
        overlap=overlap,
    )

    for chunk in chunks:
        add_document_chunk(chunk.chunk_id, chunk.text, chunk.metadata)

    return {
        "path": str(path),
        "filename": path.name,
        "course": course,
        "chunks_stored": len(chunks),
        "needs_ocr": len(chunks) == 0,
    }


def ingest_many_pdfs(
    pdf_paths: Iterable[str | Path],
    *,
    course: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_CHUNK_OVERLAP,
) -> list[dict[str, int | str | bool]]:
    """Ingest multiple PDFs with the same settings."""
    reports: list[dict[str, int | str | bool]] = []
    for pdf_path in pdf_paths:
        reports.append(
            ingest_pdf(
                pdf_path,
                course=course,
                chunk_size=chunk_size,
                overlap=overlap,
            )
        )
    return reports


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Ingest text-based PDFs into Lenslet memory.")
    parser.add_argument("pdfs", nargs="+", help="One or more PDF files to ingest.")
    parser.add_argument("--course", default="", help="Optional course or project label.")
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    parser.add_argument("--overlap", type=int, default=DEFAULT_CHUNK_OVERLAP)
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON output.")
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    reports = ingest_many_pdfs(
        args.pdfs,
        course=args.course,
        chunk_size=args.chunk_size,
        overlap=args.overlap,
    )

    if args.json:
        print(json.dumps(reports, ensure_ascii=False, indent=2))
    else:
        for report in reports:
            print(
                f"Stored {report['chunks_stored']} chunks from {report['filename']}"
                f" | needs_ocr={report['needs_ocr']}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())