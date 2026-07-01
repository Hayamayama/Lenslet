# Lenslet

Lenslet is a local-first macOS memory tool for clinicians and learners. Capture what you see on screen, copy text from anywhere, or import PDF study materials — Lenslet extracts the content, summarises it with a local or cloud LLM, auto-tags it, and stores everything in a searchable vector memory. When a clinical case makes you uncertain, Lenslet helps you find what you already learned.

```
Screen capture / Clipboard / PDF
             ↓
   Apple Vision OCR (captures)
   pdfplumber + heading-aware chunking (PDFs)
   Vision LLM for tables & diagrams (optional)
             ↓
  LLM summary + auto-tag (學習 / 生活 / 興趣)
             ↓
     Markdown memory file
             ↓
     Chroma vector index (BM25 + vector hybrid search)
             ↓
  Browse · Search · Ask · Map
```

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 14 Sonoma or later |
| Python | 3.11 or later |
| Xcode | 16 or later (to build from source) |
| Ollama | latest (for local LLM) |

### Memory requirements for local models

Lenslet defaults to `qwen3:4b` (~2.5 GB), which runs on any Apple Silicon Mac including the base 8 GB MacBook Air.

| Mac unified memory | Recommended model | Notes |
|---|---|---|
| 8 GB | `qwen3:4b` | Default. Runs comfortably alongside normal apps. |
| 16 GB | `qwen3:8b` | Better quality; switch in Settings → Model. |
| 24 GB+ | `qwen3:14b` or larger | For best quality on capable hardware. |

If your Mac has 8 GB of unified memory and you find local inference too slow, switching to Claude API in Settings → Model gives full speed with zero local resource use (requires an Anthropic API key and internet connection).

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

### 4. Build and run the macOS app

Open the Xcode project:

```
macOS/Lenslet/Lenslet.xcodeproj
```

Select your Mac as the run destination and press **⌘R**.

The first time you run, macOS will ask for **Screen Recording**, **Accessibility**, and **Notifications** permissions. Grant all three.

---

## Using Lenslet

### Menu bar

Lenslet lives in the menu bar as an eye icon. Click it to see all actions.

| Action | Shortcut | What it does |
|---|---|---|
| **Open Lenslet** | | Open the main window |
| **Capture Screen** | ⌘⇧K | Select a screen region to capture and remember |
| **Capture Clipboard** | ⌘⇧V | Save the current clipboard text directly to memory |
| **Import PDF** | | Import one or more PDFs into memory |
| **Ask Lenslet** | | Open the chat panel in the main window |
| **Documents** | | List imported PDFs |
| **Show Last Result** | | Re-open the last capture result |
| **Settings…** | ⌘, | Change model, manage memory and vector DB |
| **Quit** | | Quit the app |

Both **⌘⇧K** and **⌘⇧V** are global shortcuts — they work from any app without opening the menu bar first.

### Main window

**Sidebar (left)** — all saved memories, grouped by Today / Yesterday / This Week / Earlier. A search bar filters by title, summary, and full text. Tag chips below the search bar filter by category (學習 / 生活 / 興趣).

**Detail pane (right)** — the selected memory's summary and original text. The summary can be edited inline. Tags can be added or removed. A **Delete** button permanently removes the memory and its vector chunks. Below the content, **Related Memories** surface automatically via hybrid search.

**Ask Lenslet panel (bottom)** — a persistent scrolling chat with conversation memory. Type a question and Lenslet retrieves the most relevant chunks and generates a grounded answer. Use the **scope chips** (全部 / 學習 / 生活 / 興趣) to restrict the search to a specific category. Chat history persists until you press **Clear**.

**Knowledge Map** — toggle with the map button in the sidebar toolbar. Shows all memories as a force-directed graph. Hover to preview; click to open in the detail pane.

### Capturing a screen region

1. Press **⌘⇧K** from any app.
2. Click and drag to select the region you want to remember.
3. Lenslet runs OCR, generates a summary, auto-tags it, and saves the memory.
4. A notification confirms the save and shows how many related memories were found.

### Capturing clipboard text

1. Copy any text (from a PDF viewer, browser, EMR, etc.).
2. Press **⌘⇧V** or click **Capture Clipboard** in the menu bar.
3. Lenslet summarises and tags the text, then saves it to memory.

### Importing PDFs

1. Click **Import PDF** in the menu bar.
2. Select one or more PDF files, or a whole folder — Lenslet processes all PDFs it finds.
3. Each file is deduplicated: if a PDF was already imported, it is skipped automatically.
4. A notification confirms the import with the number of files and chunks indexed.

Lenslet uses a three-layer extraction strategy per page:

| Page type | Method |
|---|---|
| Text with tables | pdfplumber → Markdown table |
| Text with headings | Heading-aware chunking (font-size detection) |
| Diagrams / flowcharts / scanned pages | Vision LLM (if enabled) or Apple Vision OCR |

### Asking Lenslet a question

Open the **Ask Lenslet** panel at the bottom of the detail pane. Type your question in plain language. Lenslet remembers the conversation context so follow-up questions work naturally:

- *"What do I know about post-operative PT for hip replacement?"*
- *"What about complications?"* ← Lenslet understands the context from the previous turn
- *"Summarise what I captured about shoulder arthroplasty."*

Use the **scope chips** to restrict the search:
- **全部** — search all memories (default)
- **學習** — clinical and academic content only
- **生活** — daily life content only
- **興趣** — hobby and personal content only

Press **Clear** to start a new conversation thread.

### Tagging

Memories are auto-tagged at capture time using the LLM. Tags follow a fixed three-category system:

| Tag | Content |
|---|---|
| 學習 | Medicine, physical therapy, rehabilitation, anatomy, academic study |
| 生活 | Daily life, errands, food, travel, personal admin |
| 興趣 | Hobbies, sports, entertainment, personal projects |

You can edit tags manually in the detail pane at any time.

### Knowledge Map

Click the map icon (top of the sidebar) to switch to the knowledge map.

- **Node colour**: blue = screen capture, orange = PDF, green = clipboard
- **Hover**: preview panel on the right shows title, tags, and connected nodes
- **Click**: opens the memory in the detail pane
- **Drag**: pan the canvas · **Pinch**: zoom · **Reset**: return to default view

---

## Settings (⌘,)

### Project

Shows the current project folder (where `main.py` lives). Use **Change folder…** to relocate it, or **Clear saved path** to reset to the default. Lenslet will prompt you to choose a folder if it cannot find the project root.

### Model

**Ollama (local)** — fully private, runs on your Mac. Recommended models for Apple Silicon:

| Model | Size | Notes |
|---|---|---|
| `qwen3:8b` | ~5 GB | Default. Good balance of speed and quality. |
| `qwen3:4b` | ~3 GB | Faster, slightly lower quality. |

**Claude API** — uses Anthropic's Claude models. Faster and higher quality, but requires an internet connection and an API key from [console.anthropic.com](https://console.anthropic.com). The API key is stored locally at `~/.lenslet/settings.json`.

### Vision (PDF structured content)

When enabled, pages containing tables, flowcharts, or diagrams are sent to a Vision LLM for structured extraction instead of plain OCR.

- **Ollama backend**: uses `qwen2.5vl:7b` (pull with `ollama pull qwen2.5vl:7b`)
- **Claude backend**: uses the configured Claude model with vision input
- If Claude is selected but no API key is set, Lenslet falls back to Ollama automatically

When disabled (default), Lenslet uses pdfplumber for tables and Apple Vision OCR for image-heavy pages.

### Memory

Shows how many memory files are saved. **Clear all memories** deletes all Markdown files. This cannot be undone.

### Vector Database

Shows how many chunks are indexed by source. Each PDF can be removed individually.

---

## Project structure

```
Lenslet/
├── macOS/
│   └── Lenslet/                   — Swift macOS app (Xcode project)
│       └── Lenslet/
│           ├── LensletApp.swift        — app entry point, menu bar, global hotkeys, notifications
│           ├── MainWindowView.swift    — main window (sidebar + detail + chat + map toggle)
│           ├── KnowledgeMapView.swift  — force-directed knowledge map
│           ├── SettingsView.swift      — settings window
│           ├── LensletResult.swift     — data models
│           ├── MemoryStore.swift       — reads/writes memory Markdown files
│           └── ResultView.swift        — capture result popup
│
├── lenslet_core/          — Python core
│   ├── ocr.py             — Apple Vision OCR via PyObjC
│   ├── llm.py             — LLM summarise + auto-tag + Q&A (Ollama + Claude API)
│   ├── vision_llm.py      — Vision LLM for structured page analysis
│   ├── memory.py          — write Markdown memory files
│   ├── vector_memory.py   — Chroma vector store (add, hybrid search with BM25 + RRF)
│   ├── pipeline.py        — capture and clipboard pipelines
│   ├── pdf_ingest.py      — PDF extraction: heading-aware chunking, table detection, Vision routing
│   ├── query.py           — memory Q&A with conversation history and tag filter
│   ├── map.py             — knowledge graph data (cosine similarity, node/edge builder)
│   └── settings.py        — read/write ~/.lenslet/settings.json
│
├── memories/              — Markdown memory files (git-ignored)
├── chroma_db/             — Chroma vector database (git-ignored)
├── legacy/                — earlier pipeline experiments (reference only)
├── main.py                — Python CLI entry point
└── requirements.txt
```

---

## Architecture notes

**Swift owns the UI, screen capture, clipboard, and notifications.** macOS permissions (Screen Recording, Accessibility, Notifications) are easier to manage from the native app.

**Python owns OCR, LLM, memory, and vector search.** Swift calls Python via subprocess and communicates through JSON on stdout.

**Hybrid search (BM25 + vector RRF).** Every query runs both BM25 lexical ranking and Chroma vector ranking, then fuses the results with Reciprocal Rank Fusion (k=60). This handles both exact keyword matches and semantic similarity.

**Heading-aware PDF chunking.** Lenslet detects heading font sizes using PyMuPDF span metadata and splits chunks at heading boundaries. Each chunk carries a `section_heading` metadata field used to cite the source section in Ask Lenslet answers.

**Auto-tagging.** On every capture, the LLM classifies the content into a fixed tag set (學習 / 生活 / 興趣) as part of the summarisation step. Tags are stored in the Markdown memory file and in Chroma metadata for filtered search.

**Settings are shared via `~/.lenslet/settings.json`.** Both Swift (writes) and Python (reads) use this file.

---

## Development

```bash
source .venv/bin/activate

# Capture from a screenshot file
python main.py --image capture.png

# Capture from clipboard text
python main.py --text-file note.txt

# Import a single PDF
python main.py --pdf lecture.pdf

# Import multiple PDFs or a folder
python main.py --pdf-batch slides/ notes.pdf

# Search memory
python main.py --search "hip arthroplasty ROM"

# Ask a question (with optional tag scope)
python -m lenslet_core.query "What do I know about TKA rehab?" --tag 學習

# Show stats
python main.py --stats

# Generate knowledge graph data
python main.py --map
```

---

## Environment variable

```bash
LENSLET_PROJECT_ROOT=/path/to/Lenslet
```

---

## Permissions required

| Permission | Why |
|---|---|
| Screen Recording | Capturing screen regions |
| Accessibility | Global keyboard shortcuts (⌘⇧K, ⌘⇧V) |
| Notifications | Capture and import completion alerts |

All three are requested automatically on first use.

---

## Known limitations

- OCR quality depends on screenshot resolution and font clarity.
- Local Ollama models are slower than cloud APIs, especially for long contexts.
- PDF ingestion only works on text-based PDFs. Scanned PDFs require Vision LLM to be enabled.
- The app is not notarized or distributed through the App Store.
- The knowledge map requires at least 2 memories to render.
- Vision LLM page analysis (qwen2.5vl / Claude) can be slow for large PDFs with many visual pages.

---

## Roadmap

### Recently completed
- [x] Batch PDF import with folder selection
- [x] Heading-aware PDF chunking (font-size detection)
- [x] pdfplumber table extraction to Markdown
- [x] Vision LLM routing for diagrams and flowcharts
- [x] Duplicate PDF detection (skips already-imported files)
- [x] Auto-tagging with fixed categories (學習 / 生活 / 興趣)
- [x] Hybrid search (BM25 + vector RRF)
- [x] Ask Lenslet conversation memory
- [x] Ask Lenslet scope filter by tag
- [x] Inline summary editing in detail pane
- [x] Individual memory deletion with Chroma cleanup
- [x] macOS notifications on capture and import complete
- [x] Configurable project path via Settings

### Planned
- [ ] App metadata capture (active app, window title, URL) on screen capture
- [ ] Drag and drop PDF import
- [ ] Anki export (.apkg)
- [ ] Session-based memory grouping
- [ ] UMAP layout option for knowledge map
