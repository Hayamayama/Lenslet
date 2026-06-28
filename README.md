

# Lenslet

Lenslet is a local-first macOS memory capture tool.

It turns selected screen content into searchable personal memory:

```text
Screen Capture
    ↓
Apple Vision OCR
    ↓
Local LLM Summary via Ollama
    ↓
Markdown Memory
    ↓
Chroma Vector Search
    ↓
Memory Browser
```

The long-term goal is simple:

> Everything you see becomes searchable memory.

Lenslet is currently an early alpha prototype. It is built for local experimentation, not production distribution yet.

---

## Current Status

### Working

- macOS menu bar app
- Swift-owned screen capture flow
- Apple Vision OCR through Python / PyObjC
- Local summary generation through Ollama
- `qwen3:8b` local model support
- Markdown memory writing
- Chroma vector memory storage
- Related memory search
- Result window
- Memory Browser
- Open Memory
- Reveal in Finder
- Copy Summary

### Recently Stabilized

- Fixed `EXC_BAD_ACCESS` caused by AppKit window transform animation lifecycle.
- Disabled window animation for custom result/status/memory windows.
- Replaced unsafe `close()` calls with `orderOut(nil)` where appropriate.
- Kept screen capture ownership in Swift to reduce macOS Screen Recording permission issues.

---

## Project Philosophy

Lenslet is not just an OCR app.

It is not just a RAG demo.

It is becoming a local memory layer for things the user sees, reads, studies, debugs, or researches.

The product loop is:

```text
Capture
    ↓
Understand
    ↓
Remember
    ↓
Reconnect
```

Screenshot capture is only the first input source. Future sources may include PDFs, clipboard text, folders, audio, and webpages.

---

## Architecture

```text
Lenslet/
├── macOS/
│   └── Lenslet/
│       └── Lenslet/
│           ├── LensletApp.swift
│           ├── LensletResult.swift
│           ├── ResultView.swift
│           ├── MemoryStore.swift
│           ├── MemoryBrowserView.swift
│           └── ContentView.swift
│
├── lenslet_core/
│   ├── capture.py
│   ├── ocr.py
│   ├── llm.py
│   ├── memory.py
│   ├── vector_memory.py
│   └── pipeline.py
│
├── memories/
├── captures/
├── chroma_db/
├── main.py
└── requirements.txt
```

---

## Core Flow

### macOS App Flow

The macOS app owns the user-facing capture process.

```text
Menu Bar Capture
    ↓
Swift runs screencapture
    ↓
Python receives --image <path>
    ↓
OCR / LLM / Memory pipeline runs
    ↓
JSON result returns to Swift
    ↓
Result window displays summary, OCR, and related memories
```

This design is intentional. Screen capture permissions are less chaotic when capture is initiated by the macOS app instead of a Python subprocess.

### Python CLI Flow

For development and debugging, the Python pipeline can still run directly:

```bash
python main.py --json
```

Or with an existing image:

```bash
python main.py --json --image capture.png
```

---

## Requirements

### macOS

Lenslet currently targets macOS and uses Apple Vision for OCR.

### Python

Python dependencies are listed in:

```bash
requirements.txt
```

Create and activate a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Ollama

Lenslet currently expects Ollama to be running locally.

Recommended model:

```bash
ollama pull qwen3:8b
```

Start or verify Ollama:

```bash
ollama list
```

---

## Development Setup

### 1. Clone the repository

```bash
git clone <repo-url>
cd Lenslet
```

### 2. Install Python dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Install Ollama model

```bash
ollama pull qwen3:8b
```

### 4. Test the Python pipeline

```bash
source .venv/bin/activate
python -m py_compile main.py lenslet_core/*.py
python main.py --json
```

A successful result should include:

```json
{
  "status": "success",
  "ocr": "...",
  "summary": "...",
  "memory_path": "...",
  "related": [...],
  "error": null
}
```

### 5. Run the macOS app

Open:

```text
macOS/Lenslet/Lenslet.xcodeproj
```

Build and run from Xcode.

---

## Environment Variables

If the app cannot find the project root, set:

```bash
LENSLET_PROJECT_ROOT=/Users/kris/Documents/04_Research_Dev/VSC/Lenslet
```

This is useful when running from Xcode or moving the repository.

---

## Memory Format

Each captured memory is saved as Markdown in:

```text
memories/
```

Current memory format:

```markdown
# Lenslet Memory

Created: 2026-06-28T13:46:50
Source: screen_capture
Memory ID: 2026-06-28_13-46-50_3a6b73b1

## Summary

...

## Original Capture

...
```

The Memory Browser reads these Markdown files directly.

---

## Memory Browser

The Memory Browser is the first browsing layer for Lenslet memory.

Current features:

- List saved memories
- Search title / preview / summary / original text / source
- View summary and original capture
- Open memory Markdown file
- Reveal memory in Finder
- Copy summary

Menu path:

```text
Lenslet Menu Bar Icon → Memories
```

---

## Known Limitations

- OCR quality depends heavily on screenshot clarity.
- Vision OCR may normalize punctuation strangely, especially in code screenshots.
- The current memory parser expects the existing Markdown format.
- Memory search is still basic.
- Related memory scoring is not yet user-friendly.
- App metadata such as active app name, URL, or file source is not yet captured.
- The app is not packaged or notarized.

---

## Roadmap

### v0.2

- Improve Memory Browser UI
- Add memory grouping by date
- Add better search behavior
- Add direct actions to ResultView
- Improve summary formatting

### v0.3

- PDF ingestion
- Drag and drop import
- Clipboard capture
- Folder watch

### v0.4

- App metadata
- Timeline view
- Session memory
- Natural language memory retrieval

### Long-Term

- Knowledge graph
- Local-first personal research assistant
- Multi-source memory engine

---

## Development Notes

Current stable architecture rule:

```text
Swift owns UI and screen capture.
Python owns OCR, LLM, memory writing, and vector search.
```

Do not move screen capture back into Python for the app flow unless there is a clear reason. macOS Screen Recording permissions are easier to reason about when the Swift app owns capture.

For AppKit windows, avoid unnecessary `close()` calls during animated transitions. Use `orderOut(nil)` for hiding custom windows unless release is explicitly needed.

---

## Git Workflow

Recommended workflow:

```bash
git checkout -b feature/<feature-name>
```

After each stable feature:

```bash
git add .
git commit -m "feat: describe the feature"
git push origin feature/<feature-name>
```

Keep Xcode recommended setting changes in a separate commit from feature work.

---

## Current Milestone

Lenslet has reached the first usable alpha milestone:

```text
Capture → OCR → Summary → Memory → Related Search → Memory Browser
```

This is the first version where memory is no longer just an output artifact. It is now a browsable part of the product.