import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ApplicationServices
import UserNotifications

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
    private var globalHotkeyMonitor: Any?

    // MARK: Clipboard capture

    func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showErrorWindow("Clipboard is empty or contains no text.")
            return
        }

        let projectURL = self.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            showErrorWindow("Python venv not found at \(pythonURL.path)")
            return
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lenslet_clip_\(UUID().uuidString).txt")
        guard (try? text.write(to: tempURL, atomically: true, encoding: .utf8)) != nil else {
            showErrorWindow("Could not write clipboard text to temp file.")
            return
        }

        let runID = UUID().uuidString
        let resultURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lenslet_result_\(runID).json")
        let errorURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lenslet_error_\(runID).log")

        // Record active app before showing the status window
        let clipFrontApp = NSWorkspace.shared.frontmostApplication
        let clipSourceApp = clipFrontApp?.localizedName ?? ""
        let clipSourceURL = fetchBrowserURL(bundleID: clipFrontApp?.bundleIdentifier ?? "")

        showStatusWindow("Saving clipboard to memory…")

        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["main.py", "--json", "--text-file", tempURL.path]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path,
            "LENSLET_SOURCE_APP": clipSourceApp,
            "LENSLET_SOURCE_URL": clipSourceURL,
        ]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        process.terminationHandler = { [weak self] _ in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            try? data.write(to: resultURL)
            try? FileManager.default.removeItem(at: tempURL)
            DispatchQueue.main.async {
                guard let self else { return }
                self.closeStatusWindow()
                self.handlePythonResult(resultURL: resultURL, errorURL: errorURL)
            }
        }

        currentProcess = process
        try? process.run()
    }

    // MARK: Global hotkey (⌘⇧K)

    func setupGlobalHotkey() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }

        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 40 && flags == [.command, .shift] {  // keyCode 40 = K
                DispatchQueue.main.async { LensletRuntime.shared.runLenslet() }
            }
        }
    }

    var projectURL: URL {
        // 1. Explicit env var (dev / CI override)
        if let envPath = ProcessInfo.processInfo.environment["LENSLET_PROJECT_ROOT"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        // 2. User-configured path (saved via Settings or first-run picker)
        if let saved = UserDefaults.standard.string(forKey: "projectRoot"), !saved.isEmpty {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("main.py").path) {
                return url
            }
        }
        // 3. Legacy hardcoded fallback — valid path wins, avoids breaking existing setups
        let legacy = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/04_Research_Dev/VSC/Lenslet")
        if FileManager.default.fileExists(atPath: legacy.appendingPathComponent("main.py").path) {
            return legacy
        }
        // 4. Nothing found — return home so callers can detect missing main.py and prompt user
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    func promptForProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select the Lenslet project folder"
        panel.message = "Choose the folder that contains main.py and .venv"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let mainPy = url.appendingPathComponent("main.py")
            if FileManager.default.fileExists(atPath: mainPy.path) {
                UserDefaults.standard.set(url.path, forKey: "projectRoot")
            } else {
                showErrorWindow("That folder doesn't contain main.py.\n\nPlease select the root Lenslet project folder.")
            }
        }
    }

    // MARK: App metadata

    /// Returns the URL of the active browser tab for known browsers, or "" if unavailable.
    func fetchBrowserURL(bundleID: String) -> String {
        let scripts: [String: String] = [
            "com.apple.Safari":          "tell application \"Safari\" to return URL of current tab of front window",
            "com.google.Chrome":         "tell application \"Google Chrome\" to return URL of active tab of front window",
            "company.thebrowser.Browser":"tell application \"Arc\" to return URL of active tab of front window",
            "org.mozilla.firefox":       "tell application \"Firefox\" to return URL of active tab of front window",
        ]
        guard let source = scripts[bundleID],
              let appleScript = NSAppleScript(source: source) else { return "" }
        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        guard errorDict == nil else { return "" }
        return result.stringValue ?? ""
    }

    // MARK: Capture

    func runLenslet() {
        let projectURL = projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        let mainURL = projectURL.appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            promptForProjectFolder()
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

        // Record active app BEFORE screenshot overlay steals focus
        let frontApp = NSWorkspace.shared.frontmostApplication
        let captureSourceApp = frontApp?.localizedName ?? ""
        let captureSourceURL = fetchBrowserURL(bundleID: frontApp?.bundleIdentifier ?? "")

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
            "PYTHONPATH": projectURL.path,
            "LENSLET_SOURCE_APP": captureSourceApp,
            "LENSLET_SOURCE_URL": captureSourceURL,
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
        panel.title = "Import PDFs into Lenslet"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .folder]
        panel.message = "Select one or more PDF files, or a folder containing PDFs."

        guard panel.runModal() == .OK else { return }
        let selectedURLs = panel.urls
        guard !selectedURLs.isEmpty else { return }

        let projectURL = projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        let mainURL = projectURL.appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            promptForProjectFolder()
            return
        }
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            showErrorWindow("Lenslet Python virtual environment not found.\n\nExpected Python at:\n\(pythonURL.path)\n\nRun setup again or recreate .venv.")
            return
        }

        let fileCount = selectedURLs.count
        let detail = fileCount == 1
            ? "Processing \(selectedURLs[0].lastPathComponent)…"
            : "Processing \(fileCount) files…"
        showStatusWindow("Lenslet is importing PDFs…", detail: detail)

        let process = Process()
        currentProcess = process
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL

        var args = ["main.py", "--json", "--pdf-batch"]
        args += selectedURLs.map { $0.path }
        process.arguments = args
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Thread-safe collector for streaming output
        final class OutputCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var buffer = Data()
            private var lines: [String] = []

            func append(chunk: Data) { lock.withLock { buffer.append(chunk) } }

            func drainLines() -> [String] {
                lock.withLock {
                    var result: [String] = []
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                            lines.append(line)
                            result.append(line)
                        }
                    }
                    return result
                }
            }

            func flushRemaining() {
                lock.withLock {
                    if !buffer.isEmpty,
                       let line = String(data: buffer, encoding: .utf8)?
                           .trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        lines.append(line)
                        buffer = Data()
                    }
                }
            }

            func allLines() -> [String] { lock.withLock { lines } }
        }

        let collector = OutputCollector()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collector.append(chunk: chunk)

            for line in collector.drainLines() {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["type"] as? String == "file_done" {
                    let idx = json["file_index"] as? Int ?? 0
                    let total = json["total_files"] as? Int ?? fileCount
                    let name = json["filename"] as? String ?? ""
                    DispatchQueue.main.async {
                        LensletRuntime.shared.updateStatusDetail("File \(idx)/\(total): \(name)")
                    }
                }
            }
        }

        process.terminationHandler = { _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            collector.flushRemaining()
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let finalLine = collector.allLines().last(where: { $0.contains("\"status\"") }) ?? ""
            DispatchQueue.main.async {
                LensletRuntime.shared.handlePDFBatchResult(jsonLine: finalLine, errorText: errorText)
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
            promptForProjectFolder()
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
            promptForProjectFolder()
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
                let title = decoded.summary?.components(separatedBy: ".").first ?? "Saved"
                let related = decoded.related?.count ?? 0
                let body = related > 0 ? "\(related) related memor\(related == 1 ? "y" : "ies") found" : "Memory saved"
                sendNotification(title: title, body: body)
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
            // Try batch result first (--pdf-batch returns {"status","reports":[...]})
            if let batch = try? JSONDecoder().decode(BatchPdfIngestResult.self, from: outputData),
               batch.status == "success" {
                closeStatusWindow()
                showMessageWindow(title: "PDFs Imported", message: batch.displayMessage)
                return
            }
            // Single PDF fallback
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

    func updateStatusDetail(_ detail: String) {
        guard let window = statusWindow else { return }
        // Re-render the status window content with updated detail text
        window.contentView = NSHostingView(
            rootView: VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Lenslet is importing PDFs…").font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(24)
            .frame(width: 320, height: 140)
        )
    }

    func handlePDFBatchResult(jsonLine: String, errorText: String) {
        defer { currentProcess = nil }
        closeStatusWindow()

        guard !jsonLine.isEmpty,
              let data = jsonLine.data(using: .utf8),
              let batch = try? JSONDecoder().decode(BatchPdfIngestResult.self, from: data),
              batch.status == "success" else {
            showErrorWindow("PDF import failed or returned no output.\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
            return
        }
        showMessageWindow(title: "PDFs Imported", message: batch.displayMessage)
        let total = batch.reports.reduce(0) { $0 + ($1.chunks_stored ?? 0) }
        let count = batch.reports.filter { $0.skipped != true && $0.error == nil }.count
        sendNotification(title: "PDFs Imported", body: "\(count) file\(count == 1 ? "" : "s"), \(total) chunks indexed")
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

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
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

    func runChatQuery(
        question: String,
        history: [[String: String]] = [],
        tagFilter: String? = nil,
        completion: @escaping (Result<LensletQueryResult, Error>) -> Void
    ) {
        let projectURL = self.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")

        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            completion(.failure(NSError(domain: "Lenslet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python venv not found."])))
            return
        }

        // Write conversation history to a temp file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let historyURL = tempURL.appendingPathComponent("lenslet_history_\(UUID().uuidString).json")
        let historyFilePath: String? = {
            guard !history.isEmpty,
                  let historyData = try? JSONSerialization.data(withJSONObject: history) else { return nil }
            try? historyData.write(to: historyURL)
            return historyURL.path
        }()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL

        var args = ["-m", "lenslet_core.query", question, "--json"]
        if let histPath = historyFilePath {
            args += ["--history-file", histPath]
        }
        if let tag = tagFilter, !tag.isEmpty {
            args += ["--tag", tag]
        }
        process.arguments = args
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.terminationHandler = { _ in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            // Clean up history temp file
            if let histPath = historyFilePath {
                try? FileManager.default.removeItem(atPath: histPath)
            }
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

    // MARK: Memory deletion

    func deleteMemoryChunks(path: String, completion: (() -> Void)? = nil) {
        let projectURL = self.projectURL
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            completion?(); return
        }

        let escaped = path.replacingOccurrences(of: "'", with: "\\'")
        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["-c", """
import sys
sys.path.insert(0, '.')
from lenslet_core.vector_memory import collection
results = collection.get(include=['metadatas'])
ids = [
    id_ for id_, meta in zip(results['ids'], results['metadatas'] or [])
    if (meta or {}).get('path') == '\(escaped)'
]
if ids:
    collection.delete(ids=ids)
print(f'deleted {{len(ids)}} chunks for path: \(escaped)')
"""]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.terminationHandler = { _ in
            DispatchQueue.main.async { completion?() }
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
        Group {
            Button("Open Lenslet") {
                openWindow(id: "main")
            }

            Divider()

            Button("Capture Screen") {
                LensletRuntime.shared.runLenslet()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Capture Clipboard") {
                LensletRuntime.shared.captureClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

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

            SettingsLink {
                Text("Settings…")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            LensletRuntime.shared.setupGlobalHotkey()
            LensletRuntime.shared.requestNotificationPermission()
        }
    }
}
