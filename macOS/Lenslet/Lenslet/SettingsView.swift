import SwiftUI
import AppKit

// MARK: - Settings model

@Observable
final class LensletSettings {
    static let shared = LensletSettings()

    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lenslet/settings.json")
    }

    var modelBackend: String = "ollama"
    var ollamaModel: String = "qwen3:8b"
    var claudeModel: String = "claude-haiku-4-5-20251001"
    var claudeApiKey: String = ""

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.settingsURL),
              let json = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        modelBackend = json["model_backend"] ?? modelBackend
        ollamaModel  = json["ollama_model"]  ?? ollamaModel
        claudeModel  = json["claude_model"]  ?? claudeModel
        claudeApiKey = json["claude_api_key"] ?? claudeApiKey
    }

    func save() {
        let payload: [String: String] = [
            "model_backend": modelBackend,
            "ollama_model":  ollamaModel,
            "claude_model":  claudeModel,
            "claude_api_key": claudeApiKey,
        ]
        let dir = Self.settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: Self.settingsURL)
        }
    }
}

// MARK: - Stats model

struct LensletStats {
    var memoryCount: Int = 0
    var chunkCount: Int = 0
    var screenshotChunks: Int = 0
    var documentChunks: Int = 0
    var documents: [(filename: String, chunkCount: Int)] = []
}

// MARK: - Settings view

struct SettingsView: View {
    @State private var settings = LensletSettings.shared
    @State private var ollamaModels: [String] = []
    @State private var stats: LensletStats = LensletStats()
    @State private var isLoadingStats = false
    @State private var showClearMemoryConfirm = false
    @State private var documentToDelete: String? = nil

    private let claudeModels = [
        ("claude-haiku-4-5-20251001", "Haiku 4.5 — fast"),
        ("claude-sonnet-4-6",         "Sonnet 4.6 — balanced"),
    ]

    var body: some View {
        Form {
            modelSection
            memorySection
            vectorDBSection
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .padding(.vertical, 8)
        .onAppear {
            fetchOllamaModels()
            fetchStats()
        }
        .onChange(of: settings.modelBackend) { _, _ in settings.save() }
        .onChange(of: settings.ollamaModel)  { _, _ in settings.save() }
        .onChange(of: settings.claudeModel)  { _, _ in settings.save() }
    }

    // MARK: Model section

    private var modelSection: some View {
        Section("Model") {
            Picker("Backend", selection: $settings.modelBackend) {
                Text("Ollama (local)").tag("ollama")
                Text("Claude API").tag("claude")
            }
            .pickerStyle(.segmented)

            if settings.modelBackend == "ollama" {
                if ollamaModels.isEmpty {
                    HStack {
                        Text("No models found")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") { fetchOllamaModels() }
                            .buttonStyle(.borderless)
                    }
                } else {
                    Picker("Model", selection: $settings.ollamaModel) {
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                Text("Ollama must be running locally. Pull models with `ollama pull <name>`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                SecureField("API Key", text: $settings.claudeApiKey,
                            prompt: Text("sk-ant-…"))
                    .onSubmit { settings.save() }

                Picker("Model", selection: $settings.claudeModel) {
                    ForEach(claudeModels, id: \.0) { id, label in
                        Text(label).tag(id)
                    }
                }

                Text("API key is stored locally in ~/.lenslet/settings.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Memory section

    private var memorySection: some View {
        Section("Memory") {
            if isLoadingStats {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Saved memories", value: "\(stats.memoryCount)")
                LabeledContent("Screenshot chunks", value: "\(stats.screenshotChunks)")
            }

            Button("Clear all memories…", role: .destructive) {
                showClearMemoryConfirm = true
            }
            .confirmationDialog(
                "Clear all memories?",
                isPresented: $showClearMemoryConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear all memories", role: .destructive) {
                    clearAllMemories()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all Markdown memory files. Vector chunks from captures will also be removed. This cannot be undone.")
            }
        }
    }

    // MARK: Vector DB section

    private var vectorDBSection: some View {
        Section("Vector Database") {
            if isLoadingStats {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Total chunks indexed", value: "\(stats.chunkCount)")

                if !stats.documents.isEmpty {
                    ForEach(stats.documents, id: \.filename) { doc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.filename)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text("\(doc.chunkCount) chunks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                documentToDelete = doc.filename
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .confirmationDialog(
                                "Remove \"\(doc.filename)\" from memory?",
                                isPresented: Binding(
                                    get: { documentToDelete == doc.filename },
                                    set: { if !$0 { documentToDelete = nil } }
                                ),
                                titleVisibility: .visible
                            ) {
                                Button("Remove", role: .destructive) {
                                    removeDocument(filename: doc.filename)
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("All \(doc.chunkCount) chunks from this PDF will be removed from the vector index.")
                            }
                        }
                    }
                }

                Button("Refresh stats") { fetchStats() }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Actions

    private func fetchOllamaModels() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()

            let candidates = [
                "/opt/homebrew/bin/ollama",
                "/usr/local/bin/ollama",
                "/usr/bin/ollama",
            ]
            guard let ollamaPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                return
            }

            process.executableURL = URL(fileURLWithPath: ollamaPath)
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try? process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let models = output
                .components(separatedBy: .newlines)
                .dropFirst()
                .compactMap { line -> String? in
                    let name = line.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init)
                    return name?.isEmpty == false ? name : nil
                }

            DispatchQueue.main.async {
                ollamaModels = models
                if !models.isEmpty && !models.contains(settings.ollamaModel) {
                    settings.ollamaModel = models[0]
                    settings.save()
                }
            }
        }
    }

    private func fetchStats() {
        isLoadingStats = true
        let projectURL = LensletRuntime.shared.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            isLoadingStats = false
            return
        }

        let outputPipe = Pipe()
        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["main.py", "--stats"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        process.terminationHandler = { _ in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                isLoadingStats = false
                if let json = try? JSONDecoder().decode(StatsPayload.self, from: data) {
                    stats.memoryCount       = json.memory_count
                    stats.chunkCount        = json.chunk_count
                    stats.screenshotChunks  = json.screenshot_chunks
                    stats.documentChunks    = json.document_chunks
                    stats.documents = json.documents.map { ($0.filename, $0.chunk_count) }
                }
            }
        }

        try? process.run()
    }

    private func clearAllMemories() {
        let projectURL = LensletRuntime.shared.projectURL
        let memoriesURL = projectURL.appendingPathComponent("memories")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: memoriesURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "md" {
            try? FileManager.default.removeItem(at: file)
        }
        fetchStats()
        NotificationCenter.default.post(name: .lensletMemoryAdded, object: nil)
    }

    private func removeDocument(filename: String) {
        documentToDelete = nil
        let projectURL = LensletRuntime.shared.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else { return }

        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["-c", """
import sys
sys.path.insert(0, '.')
from lenslet_core.vector_memory import collection
results = collection.get(include=['metadatas'])
ids_to_delete = [
    id_ for id_, meta in zip(results['ids'], results['metadatas'] or [])
    if (meta or {}).get('filename') == '\(filename.replacingOccurrences(of: "'", with: "\\'"))'
]
if ids_to_delete:
    collection.delete(ids=ids_to_delete)
print(f'Removed {{len(ids_to_delete)}} chunks')
"""]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        process.terminationHandler = { _ in
            DispatchQueue.main.async { fetchStats() }
        }

        try? process.run()
    }
}

// MARK: - Codable helpers

private struct StatsPayload: Codable {
    let memory_count: Int
    let chunk_count: Int
    let screenshot_chunks: Int
    let document_chunks: Int
    let documents: [DocEntry]

    struct DocEntry: Codable {
        let filename: String
        let chunk_count: Int
    }
}
