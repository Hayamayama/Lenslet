from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MEMORY_DIR = PROJECT_ROOT / "memories"

MEMORY_DIR.mkdir(exist_ok=True)


def save_memory(
    ocr_text,
    summary
):

    now = datetime.now()

    filename = now.strftime(
        "%Y-%m-%d_%H-%M-%S.md"
    )

    path = MEMORY_DIR / filename


    content = f"""
# Lenslet Memory

Created:
{now.isoformat()}


## Summary

{summary}


## Original Capture

{ocr_text}

"""

    path.write_text(
        content,
        encoding="utf-8"
    )


    return path