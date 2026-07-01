"""PDF ingestion pipeline for Lenslet document memory.

Pipeline per page:
  1. PyMuPDF text extraction + page analysis (text length, image ratio, drawings)
  2. pdfplumber table detection  → structured Markdown table (text-encoded tables)
  3. If page is visual (score >= threshold):
       a. Vision LLM (Claude or qwen2.5vl) if vision_enabled  → structured Markdown
       b. Apple Vision OCR fallback                           → raw text
  4. Chunk using heading-aware strategy (falls back to character chunking)
"""

from __future__ import annotations

import hashlib
import json
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from collections.abc import Callable
from typing import Iterable

import fitz  # PyMuPDF

from lenslet_core.vector_memory import add_document_chunks_batch

DEFAULT_CHUNK_SIZE = 1400
DEFAULT_CHUNK_OVERLAP = 200

# A page scoring >= this is considered "visual" and routed to OCR / Vision LLM
VISION_SCORE_THRESHOLD = 3

# Pages with fewer extracted characters trigger visual processing
LOW_TEXT_THRESHOLD = 150

FLOWCHART_KEYWORDS = [
    "flowchart", "flow chart", "algorithm", "pathway", "workflow",
    "decision tree", "figure", "fig.", "diagram",
    "流程", "流程圖", "演算法", "路徑", "圖表", "決策",
]


# ── Data types ────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class PdfChunk:
    chunk_id: str
    text: str
    metadata: dict[str, str | int | float | bool]


@dataclass
class PageAnalysis:
    page_number: int
    text_length: int
    image_count: int
    drawing_count: int
    image_area_ratio: float
    keyword_hits: list[str]
    vision_score: int
    vision_needed: bool
    has_tables: bool


# ── Helpers ───────────────────────────────────────────────────────────────────

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _stable_pdf_id(path: Path) -> str:
    resolved = path.expanduser().resolve()
    stat = resolved.stat()
    raw = f"{resolved}:{stat.st_mtime_ns}:{stat.st_size}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _chunk_text(text: str, chunk_size: int, overlap: int) -> list[str]:
    """Character-based chunking with overlap. Used as fallback."""
    clean = "\n".join(line.strip() for line in text.splitlines() if line.strip())
    if not clean:
        return []
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


# ── Heading-aware chunking ────────────────────────────────────────────────────

def _collect_font_sizes(document: fitz.Document) -> list[float]:
    """Collect all span font sizes across the document for baseline detection."""
    sizes: list[float] = []
    for page in document:
        blocks = page.get_text("dict", flags=fitz.TEXT_PRESERVE_WHITESPACE).get("blocks", [])
        for block in blocks:
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    if span.get("text", "").strip():
                        sizes.append(span["size"])
    return sizes


def _median(values: list[float]) -> float:
    if not values:
        return 12.0
    sorted_vals = sorted(values)
    mid = len(sorted_vals) // 2
    if len(sorted_vals) % 2 == 0:
        return (sorted_vals[mid - 1] + sorted_vals[mid]) / 2
    return sorted_vals[mid]


def _is_heading(span: dict, body_size: float) -> bool:
    size = span.get("size", 0)
    flags = span.get("flags", 0)
    is_bold = bool(flags & 2 ** 4)  # bit 4 = bold in PyMuPDF
    if size > body_size * 1.2:
        return True
    if is_bold and size > body_size * 1.05:
        return True
    return False


def _extract_heading_sections(page: fitz.Page, body_size: float) -> list[dict]:
    """Return list of {heading, content} sections from a page.

    Each section starts at a heading line. Text before the first heading goes
    into a section with an empty heading. Returns [] when no structure found.
    """
    blocks = page.get_text("dict", flags=fitz.TEXT_PRESERVE_WHITESPACE).get("blocks", [])

    sections: list[dict] = []
    current_heading = ""
    current_lines: list[str] = []

    for block in blocks:
        for line in block.get("lines", []):
            spans = line.get("spans", [])
            if not spans:
                continue

            line_text = "".join(s.get("text", "") for s in spans).strip()
            if not line_text:
                continue

            # A line is a heading if the majority of its characters are heading-sized
            heading_chars = sum(
                len(s.get("text", ""))
                for s in spans
                if _is_heading(s, body_size)
            )
            total_chars = sum(len(s.get("text", "")) for s in spans)
            line_is_heading = total_chars > 0 and heading_chars / total_chars > 0.6

            if line_is_heading:
                # Save previous section
                if current_lines:
                    sections.append({
                        "heading": current_heading,
                        "content": "\n".join(current_lines),
                    })
                current_heading = line_text
                current_lines = []
            else:
                current_lines.append(line_text)

    # Flush last section
    if current_lines or current_heading:
        sections.append({
            "heading": current_heading,
            "content": "\n".join(current_lines),
        })

    return sections


def _heading_aware_chunks(
    page: fitz.Page,
    body_size: float,
    chunk_size: int,
    overlap: int,
) -> list[tuple[str, str]]:
    """Return list of (heading_prefix, chunk_text) for a page.

    Falls back to plain character chunking if no heading structure is found.
    """
    sections = _extract_heading_sections(page, body_size)

    # No headings detected → fall back to character chunking
    if not sections or all(not s["heading"] for s in sections):
        plain_text = page.get_text("text") or ""
        return [("", chunk) for chunk in _chunk_text(plain_text, chunk_size, overlap)]

    chunks: list[tuple[str, str]] = []

    for section in sections:
        heading = section["heading"]
        content = section["content"].strip()

        if not content and not heading:
            continue

        # Combine heading + content into one block
        full_text = f"{heading}\n{content}".strip() if heading else content

        if len(full_text) <= chunk_size:
            chunks.append((heading, full_text))
        else:
            # Section too long → character-split, but keep heading in first chunk
            sub_chunks = _chunk_text(full_text, chunk_size, overlap)
            for i, sub in enumerate(sub_chunks):
                chunks.append((heading if i == 0 else f"{heading} (cont.)", sub))

    return chunks if chunks else [("", page.get_text("text") or "")]


# ── Page analysis (ported from legacy vision_router.py) ───────────────────────

def _analyze_page(page: fitz.Page, page_number: int) -> PageAnalysis:
    text = page.get_text("text") or ""
    drawings = page.get_drawings()
    images = page.get_images(full=True)

    page_area = page.rect.width * page.rect.height
    image_area = 0.0
    for img in images:
        for rect in page.get_image_rects(img[0]):
            image_area += rect.width * rect.height
    image_area_ratio = image_area / page_area if page_area else 0.0

    lowered = text.lower()
    keyword_hits = [kw for kw in FLOWCHART_KEYWORDS if kw.lower() in lowered]

    score = 0
    if len(text.strip()) < LOW_TEXT_THRESHOLD:
        score += 2
    if image_area_ratio >= 0.25:
        score += 2
    if len(drawings) >= 20:
        score += 2
    if keyword_hits:
        score += 2
    if len(images) >= 3:
        score += 1

    return PageAnalysis(
        page_number=page_number,
        text_length=len(text.strip()),
        image_count=len(images),
        drawing_count=len(drawings),
        image_area_ratio=round(image_area_ratio, 4),
        keyword_hits=keyword_hits,
        vision_score=score,
        vision_needed=score >= VISION_SCORE_THRESHOLD,
        has_tables=False,  # filled in by pdfplumber pass
    )


# ── pdfplumber table extraction ───────────────────────────────────────────────

def _tables_to_markdown(pdf_path: Path, page_number: int) -> str | None:
    """Extract tables from a page using pdfplumber and return Markdown, or None."""
    try:
        import pdfplumber
    except ImportError:
        return None

    try:
        with pdfplumber.open(pdf_path) as pdf:
            # pdfplumber pages are 0-indexed
            plumber_page = pdf.pages[page_number - 1]
            tables = plumber_page.extract_tables()
            if not tables:
                return None

            md_parts: list[str] = []
            for table in tables:
                if not table or not table[0]:
                    continue
                header = table[0]
                rows = table[1:]
                col_count = len(header)

                # Build Markdown table
                def cell(v: str | None) -> str:
                    return (v or "").replace("\n", " ").strip()

                header_row = "| " + " | ".join(cell(h) for h in header) + " |"
                sep_row = "| " + " | ".join("---" for _ in range(col_count)) + " |"
                data_rows = [
                    "| " + " | ".join(cell(r[i] if i < len(r) else "") for i in range(col_count)) + " |"
                    for r in rows
                ]
                md_parts.append("\n".join([header_row, sep_row] + data_rows))

            return "\n\n".join(md_parts) if md_parts else None
    except Exception:
        return None


# ── Apple Vision OCR fallback ─────────────────────────────────────────────────

def _ocr_page(page: fitz.Page) -> str:
    """Render page to PNG and run Apple Vision OCR."""
    try:
        from lenslet_core.ocr import extract_text

        matrix = fitz.Matrix(2.0, 2.0)
        pixmap = page.get_pixmap(matrix=matrix, alpha=False)

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        pixmap.save(str(tmp_path))

        try:
            return extract_text(tmp_path)
        finally:
            tmp_path.unlink(missing_ok=True)
    except Exception:
        return ""


# ── Per-page content extraction ───────────────────────────────────────────────

def _extract_page_content(
    page: fitz.Page,
    analysis: PageAnalysis,
    pdf_path: Path,
) -> tuple[str, str]:
    """Return (final_text, extraction_method) for one page."""
    from lenslet_core.vision_llm import analyze_page as vision_analyze

    raw_text = (page.get_text("text") or "").strip()

    # ── 1. Try pdfplumber for tables first (works on text-encoded tables) ──
    table_md = _tables_to_markdown(pdf_path, analysis.page_number)
    if table_md:
        # Combine table Markdown with any surrounding paragraph text
        combined = f"{raw_text}\n\n{table_md}".strip() if raw_text else table_md
        return combined, "pdfplumber_table"

    # ── 2. If page has enough text and is not visual, use raw text ──────────
    if not analysis.vision_needed and raw_text:
        return raw_text, "text"

    # ── 3. Visual page: try Vision LLM ──────────────────────────────────────
    vision_result = vision_analyze(page)
    if vision_result:
        return vision_result, "vision_llm"

    # ── 4. Fallback: Apple Vision OCR ───────────────────────────────────────
    ocr_text = _ocr_page(page)
    if ocr_text:
        return ocr_text, "apple_vision_ocr"

    # ── 5. Last resort: whatever text PyMuPDF extracted ─────────────────────
    return raw_text, "text_partial"


# ── Public API ─────────────────────────────────────────────────────────────────

def check_pdf_already_ingested(pdf_path: str | Path) -> dict | None:
    """Return existing ingest info if this PDF is already in Chroma, else None.

    Uses the stable pdf_id (hash of path + mtime + size) as the key.
    """
    from lenslet_core.vector_memory import collection

    path = Path(pdf_path).expanduser().resolve()
    if not path.exists():
        return None

    pdf_id = _stable_pdf_id(path)
    try:
        results = collection.get(where={"pdf_id": pdf_id}, include=["metadatas"])
        ids = results.get("ids") or []
        if ids:
            metas = results.get("metadatas") or []
            ingested_at = next(
                (m.get("ingested_at", "") for m in metas if m), ""
            )
            return {
                "pdf_id": pdf_id,
                "chunk_count": len(ids),
                "ingested_at": ingested_at,
                "filename": path.name,
            }
    except Exception:
        pass
    return None


def extract_pdf_chunks(
    pdf_path: str | Path,
    *,
    course: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_CHUNK_OVERLAP,
    progress_callback: "Callable[[str], None] | None" = None,
) -> list[PdfChunk]:
    path = Path(pdf_path).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"PDF not found: {path}")
    if path.suffix.lower() != ".pdf":
        raise ValueError(f"Expected a .pdf file, got: {path}")

    pdf_id = _stable_pdf_id(path)
    ingested_at = _now_iso()
    chunks: list[PdfChunk] = []

    with fitz.open(path) as document:
        # Compute body font size baseline once across the whole document
        all_sizes = _collect_font_sizes(document)
        body_size = _median(all_sizes)

        total_pages = document.page_count
        for page_index, page in enumerate(document, start=1):
            if progress_callback:
                progress_callback(f"Page {page_index}/{total_pages}")

            try:
                analysis = _analyze_page(page, page_index)

                if analysis.vision_needed:
                    content, method = _extract_page_content(page, analysis, path)
                    page_chunk_pairs = [("", c) for c in _chunk_text(content, chunk_size, overlap)]
                else:
                    table_md = _tables_to_markdown(path, page_index)
                    if table_md:
                        raw = (page.get_text("text") or "").strip()
                        combined = f"{raw}\n\n{table_md}".strip() if raw else table_md
                        page_chunk_pairs = [("", c) for c in _chunk_text(combined, chunk_size, overlap)]
                        method = "pdfplumber_table"
                    else:
                        page_chunk_pairs = _heading_aware_chunks(page, body_size, chunk_size, overlap)
                        method = "heading_aware" if any(h for h, _ in page_chunk_pairs) else "text"

                for chunk_index, (heading, chunk_text) in enumerate(page_chunk_pairs, start=1):
                    if not chunk_text.strip():
                        continue
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
                        "extraction_method": method,
                        "vision_score": analysis.vision_score,
                    }
                    if heading:
                        metadata["section_heading"] = heading
                    chunks.append(PdfChunk(chunk_id=chunk_id, text=chunk_text, metadata=metadata))

            except Exception:
                # Skip broken pages rather than crashing the whole PDF
                continue

    return chunks


def ingest_pdf(
    pdf_path: str | Path,
    *,
    course: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_CHUNK_OVERLAP,
    progress_callback: "Callable[[str], None] | None" = None,
    force: bool = False,
) -> dict[str, int | str | bool]:
    path = Path(pdf_path).expanduser().resolve()

    if not force:
        existing = check_pdf_already_ingested(path)
        if existing:
            return {
                "path": str(path),
                "filename": path.name,
                "course": course,
                "chunks_stored": 0,
                "skipped": True,
                "reason": f"Already imported ({existing['chunk_count']} chunks, ingested {existing['ingested_at'][:10]}). Use force=True to re-ingest.",
                "extraction_methods": "{}",
            }

    chunks = extract_pdf_chunks(
        path, course=course, chunk_size=chunk_size, overlap=overlap,
        progress_callback=progress_callback,
    )

    method_counts: dict[str, int] = {}
    batch: list[tuple[str, str, dict]] = []
    for chunk in chunks:
        m = str(chunk.metadata.get("extraction_method", "text"))
        method_counts[m] = method_counts.get(m, 0) + 1
        batch.append((chunk.chunk_id, chunk.text, chunk.metadata))

    add_document_chunks_batch(batch)

    return {
        "path": str(path),
        "filename": path.name,
        "course": course,
        "chunks_stored": len(chunks),
        "extraction_methods": json.dumps(method_counts),
    }


def ingest_pdf_batch(
    paths: Iterable[str | Path],
    *,
    course: str = "",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_CHUNK_OVERLAP,
    emit_progress: bool = False,
    force: bool = False,
) -> list[dict[str, int | str | bool]]:
    """Ingest multiple PDFs sequentially. Each path may be a file or a directory.

    When emit_progress=True, prints a JSON progress line to stdout after each file
    so callers can track per-file status without waiting for the entire batch.
    """
    import sys

    # Collect all PDF files first
    all_files: list[Path] = []
    for raw in paths:
        p = Path(raw).expanduser().resolve()
        if p.is_dir():
            all_files.extend(sorted(p.glob("*.pdf")))
        elif p.suffix.lower() == ".pdf":
            all_files.append(p)

    total = len(all_files)
    reports: list[dict[str, int | str | bool]] = []

    for index, f in enumerate(all_files, start=1):
        page_status: list[str] = []

        def page_progress(msg: str, _idx: int = index, _total: int = total, _name: str = f.name) -> None:
            if emit_progress:
                print(
                    json.dumps({
                        "type": "page_progress",
                        "file_index": _idx,
                        "total_files": _total,
                        "filename": _name,
                        "msg": msg,
                    }),
                    flush=True,
                )

        try:
            report = ingest_pdf(
                f, course=course, chunk_size=chunk_size, overlap=overlap,
                progress_callback=page_progress, force=force,
            )
        except Exception as exc:
            report = {"path": str(f), "filename": f.name, "error": str(exc), "chunks_stored": 0}

        reports.append(report)

        if emit_progress:
            print(
                json.dumps({
                    "type": "file_done",
                    "file_index": index,
                    "total_files": total,
                    **{k: v for k, v in report.items()},
                }),
                flush=True,
            )

    return reports
