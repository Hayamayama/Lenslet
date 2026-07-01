from __future__ import annotations

import argparse
import json


from lenslet_core.pdf_ingest import ingest_pdf
from lenslet_core.pipeline import run_capture_pipeline

REQUIRED_RESULT_KEYS = {
    "status",
    "ocr",
    "summary",
    "memory_path",
    "related",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the Lenslet capture pipeline."
    )

    parser.add_argument(
        "--json",
        action="store_true",
        help="Output a JSON payload for the macOS Swift app.",
    )

    parser.add_argument(
        "--image",
        type=str,
        default=None,
        help="Use an existing image instead of capturing the screen.",
    )

    parser.add_argument(
        "--pdf",
        type=str,
        default=None,
        help="Ingest a PDF into Lenslet memory instead of capturing the screen.",
    )

    parser.add_argument(
        "--course",
        type=str,
        default="",
        help="Optional course or project label for PDF ingestion.",
    )

    parser.add_argument(
        "--search",
        type=str,
        default=None,
        help="Search related memories by query text and return JSON.",
    )

    parser.add_argument(
        "--top-k",
        type=int,
        default=5,
        help="Number of related memories to return for --search.",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.search:
        from lenslet_core.vector_memory import search_related
        related = search_related(args.search.strip(), n_results=args.top_k)
        if args.json:
            print(
                json.dumps(
                    {"status": "success", "related": related},
                    ensure_ascii=False,
                    indent=2,
                )
            )
        else:
            for item in related:
                print(f"- {item.get('path', '')}  distance={item.get('distance', 0):.4f}")
                print(item.get("text", "")[:200])
                print()
        return 0

    if not args.json:
        if args.pdf:
            print("📄 Ingest PDF")
        else:
            print("📸 Capture something")

    try:
        if args.pdf:
            result = ingest_pdf(
                args.pdf,
                course=args.course,
            )

            if args.json:
                print(
                    json.dumps(
                        {
                            "status": "success",
                            **result,
                        },
                        ensure_ascii=False,
                        indent=2,
                    )
                )
                return 0

            print(f"Stored {result['chunks_stored']} chunks from {result['filename']}")
            print(f"needs_ocr={result['needs_ocr']}")
            return 0

        result = run_capture_pipeline(
            image_path=args.image,
        )

        missing = REQUIRED_RESULT_KEYS - result.keys()
        if missing:
            raise RuntimeError(
                f"Pipeline returned an incomplete result. Missing keys: {sorted(missing)}"
            )

    except Exception as exc:
        error_payload = {
            "status": "error",
            "error_type": exc.__class__.__name__,
            "error": str(exc),
        }

        if args.json:
            print(
                json.dumps(
                    error_payload,
                    ensure_ascii=False,
                    indent=2,
                )
            )
        else:
            print("❌ Lenslet failed")
            print(f"{exc.__class__.__name__}: {exc}")

        return 1

    if args.json:
        payload = {
            **result,
            "error": result.get("error"),
        }
        print(
            json.dumps(
                payload,
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    print("\n====== OCR ======")
    print(result["ocr"])

    print("\n====== SUMMARY ======")
    print(result["summary"])

    print("\n====== RELATED MEMORIES ======")
    related = result.get("related", [])

    if not related:
        print("No related memories yet.")
    else:
        for item in related:
            path = item.get("path", "unknown")
            distance = item.get("distance")
            preview = item.get("text", "")[:200]

            if distance is None:
                print(f"- {path}")
            else:
                print(f"- {path}  distance={distance:.4f}")

            print(preview)
            print()

    print(f"\n💾 Saved memory: {result.get('memory_path', 'Not saved')}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())