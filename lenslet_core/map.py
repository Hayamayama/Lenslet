from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]

SIMILARITY_THRESHOLD = 0.55
MAX_EDGES_PER_NODE = 5


def _cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def _read_md_meta(path: str) -> dict[str, str]:
    """Read title and tags from a Lenslet .md memory file."""
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except Exception:
        return {}

    meta: dict[str, str] = {}
    title_candidate = ""

    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith("Tags:"):
            meta["tags"] = stripped[5:].strip()
        # First non-empty line of the Summary section as title
        if not title_candidate and stripped and not stripped.startswith("#") \
                and not any(stripped.startswith(k + ":") for k in
                            ("Created", "Source", "Memory ID", "Tags")):
            title_candidate = stripped[:80]

    # Grab first meaningful line of ## Summary section (skip label lines)
    _skip_prefixes = ("summary", "summary of", "summary:", "captured content")
    in_summary = False
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped == "## Summary":
            in_summary = True
            continue
        if in_summary and stripped.startswith("## "):
            break
        if in_summary and stripped:
            cleaned = stripped.lstrip("#").lstrip("*").rstrip("*").strip(" :")
            if cleaned.lower().rstrip(":") not in ("summary", "summary of captured content",
                                                    "captured content", "summary of"):
                meta["title"] = cleaned[:80]
                break

    if "title" not in meta:
        meta["title"] = title_candidate or Path(path).stem

    return meta


def get_graph_data() -> dict[str, Any]:
    """
    Build a memory graph for the knowledge map.

    Returns:
        {nodes: [{id, title, tags, source_type, path}],
         edges: [{source, target, weight}]}
    """
    from lenslet_core.vector_memory import collection

    results = collection.get(include=["embeddings", "metadatas"])
    ids = results.get("ids") or []
    raw_emb = results.get("embeddings")
    embeddings = raw_emb if raw_emb is not None else []
    metadatas = results.get("metadatas") or []

    if len(ids) < 2:
        return {"nodes": [], "edges": []}

    # Group chunks → one node per memory/document
    # Key: path for captures, filename for PDF chunks
    groups: dict[str, list[np.ndarray]] = {}
    group_meta: dict[str, dict] = {}

    for i, chunk_id in enumerate(ids):
        emb = np.array(embeddings[i], dtype=np.float32)
        meta = metadatas[i] or {}
        source_type = meta.get("source_type", "capture")

        if source_type in ("pdf", "document"):
            key = meta.get("filename") or chunk_id
            if key not in group_meta:
                group_meta[key] = {
                    "source_type": source_type,
                    "path": "",
                    "label": key,
                    "tags": meta.get("tags", ""),
                }
        else:
            key = meta.get("path") or chunk_id
            if key not in group_meta:
                group_meta[key] = {
                    "source_type": "capture",
                    "path": key,
                    "label": "",
                    "tags": "",
                }

        groups.setdefault(key, []).append(emb)

    if len(groups) < 2:
        return {"nodes": [], "edges": []}

    # Average embeddings per node
    node_keys = list(groups.keys())
    node_embeddings = [np.mean(groups[k], axis=0) for k in node_keys]

    # Build node list, enrich capture nodes from .md files
    nodes = []
    for key in node_keys:
        meta = group_meta[key]
        if meta["source_type"] == "capture" and meta["path"]:
            md_meta = _read_md_meta(meta["path"])
            title = md_meta.get("title", Path(meta["path"]).stem)
            tags_raw = md_meta.get("tags", "")
        else:
            title = meta["label"]
            tags_raw = meta.get("tags", "")

        tags = [t.strip() for t in tags_raw.split(",") if t.strip()] if tags_raw else []

        nodes.append({
            "id": key,
            "title": title,
            "tags": tags,
            "source_type": meta["source_type"],
            "path": meta["path"],
        })

    # Compute pairwise cosine similarity → edges
    n = len(node_keys)
    emb_matrix = np.array(node_embeddings)
    norms = np.linalg.norm(emb_matrix, axis=1, keepdims=True)
    norm_matrix = emb_matrix / (norms + 1e-8)
    sim_matrix = norm_matrix @ norm_matrix.T

    seen_edges: set[frozenset] = set()
    edges: list[dict] = []
    edges_per_node: dict[int, int] = {i: 0 for i in range(n)}

    # Sort all pairs by similarity descending
    pairs = []
    for i in range(n):
        for j in range(i + 1, n):
            pairs.append((float(sim_matrix[i, j]), i, j))
    pairs.sort(reverse=True)

    for sim, i, j in pairs:
        if sim < SIMILARITY_THRESHOLD:
            break
        if edges_per_node[i] >= MAX_EDGES_PER_NODE:
            continue
        if edges_per_node[j] >= MAX_EDGES_PER_NODE:
            continue
        key = frozenset({node_keys[i], node_keys[j]})
        if key in seen_edges:
            continue
        seen_edges.add(key)
        edges.append({"source": node_keys[i], "target": node_keys[j], "weight": round(sim, 4)})
        edges_per_node[i] += 1
        edges_per_node[j] += 1

    return {"nodes": nodes, "edges": edges}
