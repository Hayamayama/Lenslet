import subprocess
from pathlib import Path


def capture_screen():
    path = Path("capture.png")

    subprocess.run([
        "screencapture",
        "-i",
        str(path)
    ])

    return path