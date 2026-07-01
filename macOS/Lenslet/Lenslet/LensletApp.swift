import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Runtime

@MainActor
final class LensletRuntime {
    static let shared = LensletRuntime()

    var latestResult: LensletResult?
    var resultWindow: NSWindow?
    var documentBrowserWindow: NSWindow?
    var queryWindow: NSWindow?
    var statusWindow: NSWindow?
    var currentProcess: Process?

    var projectURL: URL {
        if let envPath = ProcessInfo.processInfo.environment["LENSLET_PROJECT_ROOT"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        let homeProjectURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/04_Research_Dev/VSC/Lenslet")
        if FileManager.default.fileExists(atPath: homeProjectURL.appendingPathComponent("main.py").path) {
            return homeProjectURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // MARK: Capture

    func runLenslet() {
        let projectURL = projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        let mainURL = projectURL.appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            showErrorWindow("Lenslet project root not found.\n\nExpected main.py at:\n\(mainURL.path)\n\nSet LENSLET_PROJECT_ROOT if the project moved.")
            return
        }
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            showErrorWindow("Lenslet Python virtual environment not found.\n\nExpected Python at:\n\(pythonURL.path)\n\nRun setup again or recreate .venv.")
            return
        }

        let runID = UUID().uuidString
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let captureURL = tempURL.appendingPathComponent("lenslet_capture_\(runID).png")
        let resultURL = tempURL.appendingPathComponent("lenslet_result_\(runID).json")
        let errorURL = tempURL.appendingPathComponent("lenslet_error_\(runID).log")

        try? FileManager.default.removeItem(at: captureURL)
        try? FileManager.default.removeItem(at: resultURL)
        try? FileManager.default.removeItem(at: errorURL)

        guard captureScreen(to: captureURL) else {
            print("Lenslet capture cancelled or failed.")
            return
        }

        showStatusWindow("Lenslet is thinking…")

        let command = """
        cd "\(projectURL.path)" && "\(pythonURL.path)" main.py --json --image "\(captureURL.path)" > "\(resultURL.path)" 2> "\(errorURL.path)"
        """

        let process = Process()
        currentProcess = process
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]

        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                LensletRuntime.shared.handlePythonResult(resultURL: resultURL, errorURL: errorURL)
            }
        }

        do {
            try process.run()
        } catch {
            closeStatusWindow()
            currentProcess = nil
            showErrorWindow("Failed to run Lenslet Python core.\n\n\(error.localizedDescription)")
        }
    }

    // MARK: PDF import

    func importPDF() {
        let panel = NSOpenPanel()
        panel.title = "Import PDF into Lenslet"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let pdfURL = panel.url else { return }

        let projectURL = projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        let mainURL = projectURL.appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            showErrorWindow("Lenslet project root not found.\n\nExpected main.py at:\n\(mainURL.path)\n\nSet LENSLET_PROJECT_ROOT if the project moved.")
            return
        }
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            showErrorWindow("Lenslet Python virtual environment not found.\n\nExpected Python at:\n\(pythonURL.path)\n\nRun setup again or recreate .venv.")
            return
        }

        let runID = UUID().uuidString
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let resultURL = tempURL.appendingPathComponent("lenslet_pdf_ingest_\(runID).json")
        let errorURL = tempURL.appendingPathComponent("lenslet_pdf_ingest_error_\(runID).log")

        try? FileManager.default.removeItem(at: resultURL)
        try? FileManager.default.removeItem(at: errorURL)

        showStatusWindow("Lenslet is importing PDF…", detail: "Extracting text, chunking pages, and storing vector memory.")

        let command = """
        cd "\(projectURL.path)" && "\(pythonURL.path)" main.py --json --pdf "\(pdfURL.path)" > "\(resultURL.path)" 2> "\(errorURL.path)"
        """

        let process = Process()
        currentProcess = process
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]

        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                LensletRuntime.shared.handlePDFIngestResult(resultURL: resultURL, errorURL: errorURL)
            }
        }

        do {
            try process.run()
        } catch {
            closeStatusWindow()
            currentProcess = nil
            showErrorWindow("Failed to run Lenslet PDF import.\n\n\(error.localizedDescription)")
        }
    }

    // MARK: Ask Lenslet

    func askLenslet() {
        let alert = NSAlert()
        alert.messageText = "Ask Lenslet"
        alert.informativeText = "Ask a question against your local Lenslet memory."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Ask")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
        input.placeholderString = "What do you want to ask?"
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let question = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            showErrorWindow("Ask Lenslet needs a question.")
            return
        }

        runLensletQuery(question)
    }

    func runLensletQuery(_ question: String) {
        let projectURL = projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        let mainURL = projectURL.appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            showErrorWindow("Lenslet project root not found.\n\nExpected main.py at:\n\(mainURL.path)\n\nSet LENSLET_PROJECT_ROOT if the project moved.")
            return
        }
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            showErrorWindow("Lenslet Python virtual environment not found.\n\nExpected Python at:\n\(pythonURL.path)\n\nRun setup again or recreate .venv.")
            return
        }

        showStatusWindow("Lenslet is searching memory…", detail: "Retrieving relevant chunks and generating a grounded answer.")

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let process = Process()
        currentProcess = process
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["-m", "lenslet_core.query", question, "--json"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.terminationHandler = { _ in
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                LensletRuntime.shared.handleQueryResult(outputData: outputData, errorData: errorData)
            }
        }

        do {
            try process.run()
        } catch {
            closeStatusWindow()
            currentProcess = nil
            showErrorWindow("Failed to run Lenslet query.\n\n\(error.localizedDescription)")
        }
    }

    // MARK: Documents

    func showDocuments() {
        let projectURL = projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        let mainURL = projectURL.appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            showErrorWindow("Lenslet project root not found.\n\nExpected main.py at:\n\(mainURL.path)\n\nSet LENSLET_PROJECT_ROOT if the project moved.")
            return
        }
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            showErrorWindow("Lenslet Python virtual environment not found.\n\nExpected Python at:\n\(pythonURL.path)\n\nRun setup again or recreate .venv.")
            return
        }

        showStatusWindow("Lenslet is loading documents…", detail: "Reading imported PDF metadata from local vector memory.")

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let process = Process()
        currentProcess = process
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["-m", "lenslet_core.query", "--documents", "--json"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.terminationHandler = { _ in
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                LensletRuntime.shared.handleDocumentsResult(outputData: outputData, errorData: errorData)
            }
        }

        do {
            try process.run()
        } catch {
            closeStatusWindow()
            currentProcess = nil
            showErrorWindow("Failed to load Lenslet documents.\n\n\(error.localizedDescription)")
        }
    }

    // MARK: Result handlers

    func handlePythonResult(resultURL: URL, errorURL: URL) {
        defer { currentProcess = nil }

        let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        if !errorText.isEmpty { print(errorText) }

        guard let outputData = try? Data(contentsOf: resultURL), !outputData.isEmpty else {
            closeStatusWindow()
            showErrorWindow("Lenslet returned no JSON output.\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
            return
        }

        if let outputText = String(data: outputData, encoding: .utf8) { print(outputText) }

        do {
            let decoded = try JSONDecoder().decode(LensletResult.self, from: outputData)
            closeStatusWindow()
            latestResult = decoded
            showResultWindow(decoded)
            if decoded.isSuccess {
                NotificationCenter.default.post(name: .lensletMemoryAdded, object: nil)
            }
        } catch {
            closeStatusWindow()
            let outputText = String(data: outputData, encoding: .utf8) ?? "<non UTF-8 output>"
            showErrorWindow("Failed to decode Lenslet JSON.\n\n\(error.localizedDescription)\n\nOutput:\n\(outputText)\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
        }
    }

    func handlePDFIngestResult(resultURL: URL, errorURL: URL) {
        defer { currentProcess = nil }

        let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        if !errorText.isEmpty { print(errorText) }

        guard let outputData = try? Data(contentsOf: resultURL), !outputData.isEmpty else {
            closeStatusWindow()
            showErrorWindow("Lenslet returned no PDF ingest JSON output.\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
            return
        }

        if let outputText = String(data: outputData, encoding: .utf8) { print(outputText) }

        do {
            let decoded = try JSONDecoder().decode(PdfIngestResult.self, from: outputData)
            closeStatusWindow()
            if decoded.isSuccess {
                showMessageWindow(title: "PDF Imported", message: decoded.displayMessage)
            } else {
                showErrorWindow(decoded.displayMessage)
            }
        } catch {
            closeStatusWindow()
            let outputText = String(data: outputData, encoding: .utf8) ?? "<non UTF-8 output>"
            showErrorWindow("Failed to decode Lenslet PDF ingest JSON.\n\n\(error.localizedDescription)\n\nOutput:\n\(outputText)\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
        }
    }

    func handleQueryResult(outputData: Data, errorData: Data) {
        defer { currentProcess = nil }

        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        if !errorText.isEmpty { print(errorText) }

        guard !outputData.isEmpty else {
            closeStatusWindow()
            showErrorWindow("Lenslet returned no query JSON output.\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
            return
        }

        if let outputText = String(data: outputData, encoding: .utf8) { print(outputText) }

        do {
            let decoded = try JSONDecoder().decode(LensletQueryResult.self, from: outputData)
            closeStatusWindow()
            showQueryResultWindow(decoded)
        } catch {
            closeStatusWindow()
            let outputText = String(data: outputData, encoding: .utf8) ?? "<non UTF-8 output>"
            showErrorWindow("Failed to decode Lenslet query JSON.\n\n\(error.localizedDescription)\n\nOutput:\n\(outputText)\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
        }
    }

    func handleDocumentsResult(outputData: Data, errorData: Data) {
        defer { currentProcess = nil }

        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        if !errorText.isEmpty { print(errorText) }

        guard !outputData.isEmpty else {
            closeStatusWindow()
            showErrorWindow("Lenslet returned no documents JSON output.\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
            return
        }

        if let outputText = String(data: outputData, encoding: .utf8) { print(outputText) }

        do {
            let decoded = try JSONDecoder().decode(DocumentListResult.self, from: outputData)
            closeStatusWindow()
            showDocumentBrowserWindow(documents: decoded.documents)
        } catch {
            closeStatusWindow()
            let outputText = String(data: outputData, encoding: .utf8) ?? "<non UTF-8 output>"
            showErrorWindow("Failed to decode Lenslet documents JSON.\n\n\(error.localizedDescription)\n\nOutput:\n\(outputText)\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
        }
    }

    // MARK: Screen capture

    func captureScreen(to outputURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", outputURL.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to run screencapture:", error)
            return false
        }

        guard process.terminationStatus == 0 else { return false }
        guard FileManager.default.fileExists(atPath: outputURL.path) else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0 else { return false }

        return true
    }

    // MARK: Windows

    func showStatusWindow(_ message: String, detail: String = "OCR, summary, and memory search are running.") {
        closeStatusWindow()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.title = "Lenslet"
        window.contentView = NSHostingView(
            rootView: VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(message).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 320, height: 140)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusWindow = window
    }

    func closeStatusWindow() {
        statusWindow?.orderOut(nil)
    }

    func showErrorWindow(_ message: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.title = "Lenslet Error"
        window.contentView = NSHostingView(
            rootView: ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Lenslet hit an error")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(message)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
            .frame(width: 640, height: 420)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMessageWindow(title: String, message: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.title = title
        window.contentView = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title2).fontWeight(.semibold)
                Text(message).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button("OK") { window.close() }
                    .keyboardShortcut(.defaultAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
            .frame(width: 460, height: 220)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showResultWindow(_ result: LensletResult) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        resultWindow?.orderOut(nil)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.title = "Lenslet"
        window.contentView = NSHostingView(rootView: ResultView(result: result))

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        resultWindow = window
    }

    func showQueryResultWindow(_ result: LensletQueryResult) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        queryWindow?.orderOut(nil)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.title = "Ask Lenslet"
        window.contentView = NSHostingView(
            rootView: ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question").font(.caption).foregroundStyle(.secondary)
                        Text(result.question).font(.headline).textSelection(.enabled)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Answer").font(.caption).foregroundStyle(.secondary)
                        Text(result.answer).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sources").font(.headline)
                        if result.sources.isEmpty {
                            Text("No sources returned.").foregroundStyle(.secondary)
                        } else {
                            ForEach(result.sources) { source in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(source.displayTitle).font(.subheadline).fontWeight(.semibold).textSelection(.enabled)
                                    Text(source.displayLocation).font(.caption).foregroundStyle(.secondary)
                                    if let text = source.text, !text.isEmpty {
                                        Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(24)
            }
            .frame(width: 760, height: 620)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        queryWindow = window
    }

    func showDocumentBrowserWindow(documents: [DocumentSummary]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        documentBrowserWindow?.orderOut(nil)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.title = "Lenslet Documents"
        window.contentView = NSHostingView(
            rootView: ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Documents").font(.title2).fontWeight(.semibold)
                            Text("Imported PDFs in local vector memory").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(documents.count) files").font(.caption).foregroundStyle(.secondary)
                    }

                    if documents.isEmpty {
                        Text("No imported documents found.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(documents) { document in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "doc.richtext").font(.title2).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(document.filename).font(.headline).textSelection(.enabled)
                                        Text(document.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                                        HStack(spacing: 12) {
                                            Text("\(document.page_count) pages")
                                            Text("\(document.chunk_count) chunks")
                                            Text(document.displayCourse)
                                        }
                                        .font(.caption).foregroundStyle(.secondary)
                                        Text("Imported: \(document.displayImportedAt)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(24)
            }
            .frame(width: 780, height: 560)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        documentBrowserWindow = window
    }

    // MARK: Chat query

    func runChatQuery(question: String, completion: @escaping (Result<LensletQueryResult, Error>) -> Void) {
        let projectURL = self.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")

        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            completion(.failure(NSError(domain: "Lenslet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python venv not found."])))
            return
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["-m", "lenslet_core.query", question, "--json"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.terminationHandler = { _ in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                do {
                    let result = try JSONDecoder().decode(LensletQueryResult.self, from: data)
                    completion(.success(result))
                } catch {
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    completion(.failure(NSError(domain: "Lenslet", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to decode response.\n\(raw)\n\(stderr)"
                    ])))
                }
            }
        }

        try? process.run()
    }

    // MARK: Related memory search

    func searchRelated(query: String, topK: Int = 5, completion: @escaping ([RelatedMemory]) -> Void) {
        let projectURL = self.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")

        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            completion([])
            return
        }

        let outputPipe = Pipe()
        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["main.py", "--json", "--search", query, "--top-k", String(topK)]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        process.terminationHandler = { _ in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                struct SearchResult: Codable {
                    let status: String
                    let related: [RelatedMemory]?
                }
                let related = (try? JSONDecoder().decode(SearchResult.self, from: data))?.related ?? []
                completion(related)
            }
        }

        try? process.run()
    }
}

// MARK: - Document models

struct DocumentListResult: Codable {
    let documents: [DocumentSummary]
}

struct DocumentSummary: Codable, Hashable, Identifiable {
    let id: String
    let filename: String
    let path: String
    let source_type: String
    let course: String
    let chunk_count: Int
    let last_ingested_at: String
    let pages: [Int]
    let page_count: Int

    var displayCourse: String {
        course.isEmpty ? "Unknown course" : course
    }

    var displayImportedAt: String {
        last_ingested_at.isEmpty ? "Unknown import time" : last_ingested_at
    }
}

// MARK: - App

@main
struct LensletApp: App {
    var body: some Scene {
        Window("Lenslet", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
        }

        MenuBarExtra("Lenslet", systemImage: "eye") {
            MenuBarView()
        }
    }
}

// MARK: - Menu bar

private struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Lenslet") {
            openWindow(id: "main")
        }

        Divider()

        Button("Capture") {
            LensletRuntime.shared.runLenslet()
        }

        Button("Import PDF") {
            LensletRuntime.shared.importPDF()
        }

        Button("Ask Lenslet") {
            LensletRuntime.shared.askLenslet()
        }

        Button("Documents") {
            LensletRuntime.shared.showDocuments()
        }

        Button("Show Last Result") {
            if let result = LensletRuntime.shared.latestResult {
                LensletRuntime.shared.showResultWindow(result)
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
