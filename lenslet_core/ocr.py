from __future__ import annotations

from pathlib import Path

import Vision
from Foundation import NSURL

RECOGNITION_LANGUAGES = [
    "zh-Hant",
    "zh-Hans",
    "en-US",
    "ja-JP",
]


def extract_text(image_path: str | Path) -> str:
    image_path = Path(image_path).expanduser().resolve()

    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    url = NSURL.fileURLWithPath_(str(image_path))

    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    request.setRecognitionLanguages_(RECOGNITION_LANGUAGES)
    request.setUsesLanguageCorrection_(True)

    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(
        url,
        None,
    )

    success, error = handler.performRequests_error_(
        [request],
        None,
    )

    if not success:
        raise RuntimeError(f"Vision OCR failed: {error}")

    results = request.results() or []
    texts: list[str] = []

    for observation in results:
        candidates = observation.topCandidates_(1)
        if not candidates:
            continue

        candidate = candidates[0]
        text = candidate.string()
        if text:
            texts.append(str(text).strip())

    return "\n".join(text for text in texts if text)