# Lenslet

Lenslet is a local-first macOS memory tool. It captures what you see on screen, extracts the text, summarises it with a local or cloud LLM, and stores everything in a searchable vector memory. When you see something clinical, academic, or just interesting, Lenslet remembers it so you can find it later.

```
Screen capture / PDF
       ↓
Apple Vision OCR
       ↓
LLM summary (Ollama or Claude API)
       ↓
Markdown memory file
       ↓
Chroma vector index
       ↓
Main window — browse, search, ask
```

> Early alpha. Built for personal use on macOS.

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14 Sonoma or later |
| Python | 3.11 or later |
| Xcode | 16 or later |
| Ollama | latest (for local LLM) |

---

## Setup

### 1. Clone the repository

```bash
git clone <repo-url>
cd Lenslet
```

### 2. Create a Python virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Install Ollama

Download Ollama from [ollama.com](https://ollama.com) and install it.

Then pull a model. Lenslet defaults to `qwen3:8b`, which runs well on Apple Silicon:

```bash
ollama pull qwen3:8b
```

Start Ollama (it runs as a background service after installation):

```bash
ollama serve
```

Verify it is running:

```bash
ollama list
```

You should see `qwen3:8b` in the list.

### 4. Build and run the macOS app

Open the Xcode project:

```
macOS/Lenslet/Lenslet.xcodeproj
```

Select your Mac as the run destination and press **⌘R**.

The first time you run, macOS will ask for **Screen Recording** permission. Grant it so Lenslet can capture your screen.

---

## Using Lenslet

### Menu bar

Lenslet lives in the menu bar as an eye icon. Click it to see all actions.

| Action | What it does |
|---|---|
| **Open Lenslet** | Open the main window |
| **Capture** | Select a region of the screen to capture and remember |
| **Import PDF** | Import a PDF (lecture slides, paper, handout) into memory |
| **Ask Lenslet** | Ask a question against your memory (opens chat in main window) |
| **Documents** | List imported PDFs |
| **Show Last Result** | Re-open the last capture result |
| **Settings…** | Change model, manage memory and vector DB |
| **Quit** | Quit the app |

### Main window (⌘,)

The main window has three areas:

**Sidebar (left)** — all saved memories, grouped by Today / Yesterday / This Week / Earlier. Search bar at the top filters by title, summary, and full text.

**Detail pane (right)** — the selected memory's summary and original OCR text. Below the content, **Related Memories** appear automatically — Lenslet runs a vector search on the current memory and surfaces the most relevant things you have captured before.

**Ask Lenslet panel (bottom)** — a persistent chat panel. Click the header to expand it. Type a question and Lenslet searches your memory, retrieves the most relevant chunks, and generates a grounded answer. Chat history is kept for the session.

### Capturing a screen region

1. Click **Capture** in the menu bar.
2. Click and drag to select the region you want to remember.
3. Lenslet runs OCR, generates a summary, and saves the memory.
4. The result window shows the summary and related memories from before.

### Importing a PDF

1. Click **Import PDF** in the menu bar.
2. Select a text-based PDF (lecture slides, papers, handouts).
3. Lenslet extracts the text, splits it into chunks, and stores them in the shared vector index.

PDF chunks and screen capture memories live in the same vector index, so asking Lenslet a question will search across both.

### Asking Lenslet a question

Open the **Ask Lenslet** panel at the bottom of the main window. Type your question in plain language:

- *"What do I know about post-operative PT for hip replacement?"*
- *"This patient has limited knee flexion after TKA, what exercises do I have notes on?"*
- *"Summarise what I captured about fracture management."*

Lenslet retrieves the most relevant memory chunks and uses the LLM to generate a grounded answer with source references.

---

## Settings (⌘,)

Open Settings from the menu bar or with **⌘,**.

### Model

Choose between two backends:

**Ollama (local)** — fully private, runs on your Mac. Requires Ollama to be running. The model dropdown lists all models currently installed. To add a model:

```bash
ollama pull <model-name>
```

Recommended models for Apple Silicon:

| Model | Size | Notes |
|---|---|---|
| `qwen3:8b` | ~5 GB | Default. Good balance of speed and quality. |
| `qwen3:4b` | ~3 GB | Faster, slightly lower quality. |
| `llama3.2:3b` | ~2 GB | Lightweight option. |

**Claude API** — uses Anthropic's Claude models. Faster and higher quality, but requires an internet connection and an API key.

1. Get an API key at [console.anthropic.com](https://console.anthropic.com).
2. Paste it into the API Key field in Settings.
3. Choose a model:
   - **Haiku 4.5** — fast and cheap, good for everyday captures.
   - **Sonnet 4.6** — smarter, better for complex clinical or research questions.

The API key is stored locally at `~/.lenslet/settings.json` and never sent anywhere except the Anthropic API.

### Memory

Shows how many memory files are saved. **Clear all memories** deletes all Markdown memory files from disk. This cannot be undone.

### Vector Database

Shows how many chunks are indexed and breaks them down by PDF. Each PDF can be removed individually — this removes its chunks from the vector index without affecting your other memories.

---

## Project structure

```
Lenslet/
├── macOS/
│   └── Lenslet/          — Swift macOS app (Xcode project)
│       └── Lenslet/
│           ├── LensletApp.swift        — app entry point, menu bar, window management
│           ├── MainWindowView.swift    — main window (sidebar + detail + chat)
│           ├── SettingsView.swift      — settings window
│           ├── LensletResult.swift     — data models
│           ├── MemoryStore.swift       — reads memory Markdown files
│           ├── MemoryBrowserView.swift — legacy browser (kept for reference)
│           ├── ResultView.swift        — capture result popup
│           └── ContentView.swift       — unused placeholder
│
├── lenslet_core/          — Python core
│   ├── capture.py         — fallback screen capture (not used in app flow)
│   ├── ocr.py             — Apple Vision OCR via PyObjC
│   ├── llm.py             — LLM summarise and Q&A (Ollama + Claude API)
│   ├── memory.py          — write Markdown memory files
│   ├── vector_memory.py   — Chroma vector store (add, search)
│   ├── pipeline.py        — full capture pipeline
│   ├── pdf_ingest.py      — PDF extraction and chunking
│   ├── query.py           — memory Q&A CLI entry point
│   └── settings.py        — read/write ~/.lenslet/settings.json
│
├── memories/              — Markdown memory files (git-ignored)
├── chroma_db/             — Chroma vector database (git-ignored)
├── main.py                — Python CLI entry point
└── requirements.txt
```

---

## Architecture notes

**Swift owns the UI and screen capture.** macOS Screen Recording permissions are easier to manage when the native app initiates the capture rather than a Python subprocess.

**Python owns OCR, LLM, memory, and vector search.** Swift calls Python via subprocess and communicates through JSON on stdout.

**Settings are shared via `~/.lenslet/settings.json`.** Both Swift (writes) and Python (reads) use this file so model selection in the UI takes effect immediately for all pipeline operations.

---

## Development

To test the Python pipeline directly without the app:

```bash
source .venv/bin/activate

# Capture and process a screenshot interactively
python main.py

# Process an existing image
python main.py --image capture.png

# Import a PDF
python main.py --pdf lecture.pdf

# Search memory
python main.py --search "hip arthroplasty ROM"

# Ask a question
python -m lenslet_core.query "What do I know about post-op PT for THA?"

# Show stats
python main.py --stats
```

All commands accept `--json` for machine-readable output.

---

## Environment variable

If Lenslet cannot find the project root (for example when running from Xcode with a non-standard path), set:

```bash
LENSLET_PROJECT_ROOT=/path/to/Lenslet
```

---

## Known limitations

- OCR quality depends on screenshot resolution and font clarity.
- Local Ollama models are slower than cloud APIs, especially for long contexts.
- PDF ingestion only works on text-based PDFs. Scanned PDFs need OCR pre-processing.
- The app is not notarized or distributed through the App Store.

---

## Roadmap

- [ ] Visual knowledge map (embedding space visualisation)
- [ ] Clipboard capture
- [ ] Drag and drop import
- [ ] Session-based memory grouping
- [ ] App metadata capture (active app, URL)
