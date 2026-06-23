import Vision
from Foundation import NSURL


def extract_text(image_path):

    url = NSURL.fileURLWithPath_(str(image_path.absolute()))

    request = Vision.VNRecognizeTextRequest.alloc().init()

    request.setRecognitionLevel_(
        Vision.VNRequestTextRecognitionLevelAccurate
    )
    request.setRecognitionLanguages_([
    "zh-Hant",
    "zh-Hans",
    "en-US",
    "ja-JP"
])
    request.setUsesLanguageCorrection_(True)
    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(
        url,
        None
    )

    success = handler.performRequests_error_(
        [request],
        None
    )

    results = request.results()

    texts = []

    for observation in results:
        candidate = observation.topCandidates_(1)[0]
        texts.append(candidate.string())

    return "\n".join(texts)