from __future__ import annotations

import argparse
import json

from lenslet_core.pipeline import run_capture_pipeline


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
        print(
            json.dumps(
                result,
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

    print(f"\n💾 Saved memory: {result['memory_path']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())