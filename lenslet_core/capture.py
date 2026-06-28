from __future__ import annotations

import subprocess
from pathlib import Path
from uuid import uuid4

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CAPTURE_DIR = PROJECT_ROOT / "captures"

CAPTURE_DIR.mkdir(parents=True, exist_ok=True)


def capture_screen(output_path: str | Path | None = None) -> Path:
    if output_path is None:
        output_path = CAPTURE_DIR / f"capture_{uuid4().hex[:8]}.png"
    else:
        output_path = Path(output_path).expanduser().resolve()

    output_path.parent.mkdir(parents=True, exist_ok=True)

    completed = subprocess.run(
        [
            "screencapture",
            "-i",
            str(output_path),
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        raise RuntimeError(
            f"screencapture failed with exit code {completed.returncode}."
            + (f" stderr: {stderr}" if stderr else "")
        )

    if not output_path.exists():
        raise RuntimeError(
            "No screenshot was created. The capture may have been cancelled."
        )

    if output_path.stat().st_size == 0:
        raise RuntimeError(f"Screenshot file is empty: {output_path}")

    return output_path