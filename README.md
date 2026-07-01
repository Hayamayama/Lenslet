# Lenslet

Lenslet is a local-first macOS memory tool for clinicians and learners. Capture what you see on screen, copy text from anywhere, or import PDF study materials — Lenslet extracts the content, summarises it with a local or cloud LLM, and stores everything in a searchable vector memory. When a clinical case makes you uncertain, Lenslet helps you find what you already learned.

```
Screen capture / Clipboard / PDF
             ↓
   Apple Vision OCR (captures)
             ↓
  LLM summary (Ollama or Claude)
             ↓
     Markdown memory file
             ↓
     Chroma vector index
             ↓
  Browse · Search · Ask · Map
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
git clone https://github.com/Hayamayama/Lenslet.git
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

Pull a model. Lenslet defaults to `qwen3:8b`, which runs well on Apple Silicon:

```bash
ollama pull qwen3:8b
ollama serve
```

Verify it is running:

```bash
ollama list
```

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

Lenslet lives in the menu bar as an eye icon (⊙). Click it to see all actions.

| Action | Shortcut | What it does |
|---|---|---|
| **Open Lenslet** | | Open the main window |
| **Capture Screen** | ⌘⇧K | Select a screen region to capture and remember |
| **Capture Clipboard** | ⌘⇧V | Save the current clipboard text directly to memory |
| **Import PDF** | | Import a PDF into memory |
| **Ask Lenslet** | | Open the chat panel in the main window |
| **Documents** | | List imported PDFs |
| **Show Last Result** | | Re-open the last capture result |
| **Settings…** | ⌘, | Change model, manage memory and vector DB |
| **Quit** | | Quit the app |

Both **⌘⇧K** and **⌘⇧V** are global shortcuts — they work from any app without opening the menu bar first. The first time you use them, macOS will ask for **Accessibility** permission.

### Main window

The main window has four areas:

**Sidebar (left)** — all saved memories, grouped by Today / Yesterday / This Week / Earlier. A search bar filters by title, summary, and full text. Tag chips below the search bar let you filter by category.

**Detail pane (right)** — the selected memory's summary and original text. Tags can be added or removed inline. Below the content, **Related Memories** surface automatically via vector search.

**Ask Lenslet panel (bottom of detail pane)** — a persistent scrolling chat. Type a question and Lenslet retrieves the most relevant memory chunks and generates a grounded answer. Chat history is kept for the session.

**Knowledge Map** — toggle with the map button (⊙) in the sidebar toolbar. Shows all memories as a force-directed graph: nodes are memories, edges connect similar ones. Hover a node to preview it in the right panel; click to open it in the detail pane.

### Capturing a screen region

1. Press **⌘⇧K** from any app, or click **Capture Screen** in the menu bar.
2. Click and drag to select the region you want to remember.
3. Lenslet runs OCR, generates a summary, and saves the memory.
4. The result window shows the summary and related past memories.

### Capturing clipboard text

1. Copy any text (from a PDF viewer, browser, EMR, etc.).
2. Press **⌘⇧V** or click **Capture Clipboard** in the menu bar.
3. Lenslet summarises the text and saves it to memory — no screenshot needed.

### Importing a PDF

1. Click **Import PDF** in the menu bar.
2. Select a text-based PDF (lecture slides, papers, handouts).
3. Lenslet extracts the text, splits it into chunks, and stores them in the shared vector index.

PDF chunks and screen captures live in the same vector index, so asking a question searches across both.

### Asking Lenslet a question

Open the **Ask Lenslet** panel at the bottom of the detail pane. Type your question in plain language:

- *"What do I know about post-operative PT for hip replacement?"*
- *"This patient has limited knee flexion after TKA, what exercises do I have notes on?"*
- *"Summarise what I captured about shoulder arthroplasty."*

### Tagging memories

Open any memory in the detail pane. Click **+ Add tag** below the title to type a tag and press Return. Click the **✕** on any tag to remove it. Tags are saved immediately to the memory file.

Use the tag filter chips in the sidebar to view only memories with a specific tag.

### Knowledge Map

Click the map icon (top of the sidebar) to switch to the knowledge map. The map runs a force-directed simulation to cluster memories by semantic similarity.

- **Node colour**: blue = screen capture, orange = PDF, green = clipboard
- **Edge weight**: proportional to cosine similarity between memories
- **Hover**: preview panel on the right shows the title, tags, and connected nodes
- **Click**: selects the memory and switches back to the detail view
- **Drag**: pan the canvas
- **Pinch**: zoom in/out
- **Reset** button: returns to the default position and scale

---

## Settings (⌘,)

Open Settings from the menu bar or with **⌘,**.

### Model

Choose between two backends:

**Ollama (local)** — fully private, runs on your Mac. Requires Ollama to be running. The model dropdown lists all currently installed models. To add a model:

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
   - **Sonnet 4.6** — smarter, better for complex clinical questions.

The API key is stored locally at `~/.lenslet/settings.json` and never sent anywhere except the Anthropic API.

### Memory

Shows how many memory files are saved. **Clear all memories** deletes all Markdown memory files. This cannot be undone.

### Vector Database

Shows how many chunks are indexed, broken down by source. Each PDF can be removed individually without affecting other memories.

---

## Project structure

```
Lenslet/
├── macOS/
│   └── Lenslet/                   — Swift macOS app (Xcode project)
│       └── Lenslet/
│           ├── LensletApp.swift        — app entry point, menu bar, global hotkeys
│           ├── MainWindowView.swift    — main window (sidebar + detail + chat + map toggle)
│           ├── KnowledgeMapView.swift  — force-directed knowledge map
│           ├── SettingsView.swift      — settings window
│           ├── LensletResult.swift     — data models
│           ├── MemoryStore.swift       — reads/writes memory Markdown files
│           └── ResultView.swift        — capture result popup
│
├── lenslet_core/          — Python core
│   ├── ocr.py             — Apple Vision OCR via PyObjC
│   ├── llm.py             — LLM summarise and Q&A (Ollama + Claude API)
│   ├── memory.py          — write Markdown memory files
│   ├── vector_memory.py   — Chroma vector store (add, search)
│   ├── pipeline.py        — capture and clipboard pipelines
│   ├── pdf_ingest.py      — PDF extraction and chunking
│   ├── query.py           — memory Q&A CLI entry point
│   ├── map.py             — knowledge graph data (cosine similarity, node/edge builder)
│   └── settings.py        — read/write ~/.lenslet/settings.json
│
├── memories/              — Markdown memory files (git-ignored)
├── chroma_db/             — Chroma vector database (git-ignored)
├── main.py                — Python CLI entry point
└── requirements.txt
```

---

## Architecture notes

**Swift owns the UI, screen capture, and clipboard.** macOS permissions (Screen Recording, Accessibility) are easier to manage when the native app initiates these actions.

**Python owns OCR, LLM, memory, and vector search.** Swift calls Python via subprocess and communicates through JSON on stdout.

**Settings are shared via `~/.lenslet/settings.json`.** Both Swift (writes) and Python (reads) use this file so model changes take effect immediately.

**Tags are stored in the Markdown memory file** under a `Tags:` metadata line and read back by `MemoryStore` on every load.

---

## Development

To test the Python pipeline directly:

```bash
source .venv/bin/activate

# Capture from a screenshot file
python main.py --image capture.png

# Capture from clipboard text file
python main.py --text-file note.txt

# Import a PDF
python main.py --pdf lecture.pdf

# Search memory
python main.py --search "hip arthroplasty ROM"

# Ask a question
python -m lenslet_core.query "What do I know about post-op PT for THA?"

# Show stats
python main.py --stats

# Generate knowledge graph data
python main.py --map
```

All commands accept `--json` for machine-readable output.

---

## Environment variable

If Lenslet cannot find the project root, set:

```bash
LENSLET_PROJECT_ROOT=/path/to/Lenslet
```

---

## Permissions required

| Permission | Why |
|---|---|
| Screen Recording | Capturing screen regions |
| Accessibility | Global keyboard shortcuts (⌘⇧K, ⌘⇧V) |

Both are requested automatically on first use.

---

## Known limitations

- OCR quality depends on screenshot resolution and font clarity.
- Local Ollama models are slower than cloud APIs, especially for long contexts.
- PDF ingestion only works on text-based PDFs. Scanned PDFs need OCR pre-processing.
- The app is not notarized or distributed through the App Store.
- The knowledge map requires at least 2 memories to render.

---

## Roadmap

- [ ] Drag and drop import
- [ ] Session-based memory grouping
- [ ] App metadata capture (active app, URL)
- [ ] UMAP layout option for knowledge map
