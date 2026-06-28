from __future__ import annotations

import argparse
import json


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

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not args.json:
        print("📸 Capture something")

    try:
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