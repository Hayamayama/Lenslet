import SwiftUI
import AppKit

@MainActor
final class LensletRuntime {
    static let shared = LensletRuntime()

    var latestResult: LensletResult?
    var resultWindow: NSWindow?
    var memoryBrowserWindow: NSWindow?
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
}

@main
struct LensletApp: App {
    private let runtime = LensletRuntime.shared

    var body: some Scene {
        MenuBarExtra("Lenslet", systemImage: "eye") {
            Button("Capture") {
                runLenslet()
            }

            Button("Show Result") {
                if let result = runtime.latestResult {
                    showResultWindow(result)
                }
            }

            Button("Memories") {
                showMemoryBrowserWindow()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func runLenslet() {
        let projectURL = runtime.projectURL
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
        runtime.currentProcess = process
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]

        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                handlePythonResult(resultURL: resultURL, errorURL: errorURL)
            }
        }

        do {
            try process.run()
        } catch {
            closeStatusWindow()
            runtime.currentProcess = nil
            showErrorWindow("Failed to run Lenslet Python core.\n\n\(error.localizedDescription)")
        }
    }

    func handlePythonResult(resultURL: URL, errorURL: URL) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                handlePythonResult(resultURL: resultURL, errorURL: errorURL)
            }
            return
        }

        defer {
            runtime.currentProcess = nil
        }

        let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        if !errorText.isEmpty {
            print(errorText)
        }

        guard let outputData = try? Data(contentsOf: resultURL),
              !outputData.isEmpty else {
            closeStatusWindow()
            showErrorWindow("Lenslet returned no JSON output.\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
            return
        }

        if let outputText = String(data: outputData, encoding: .utf8) {
            print(outputText)
        }

        do {
            let decoded = try JSONDecoder().decode(
                LensletResult.self,
                from: outputData
            )

            closeStatusWindow()
            runtime.latestResult = decoded
            showResultWindow(decoded)

        } catch {
            closeStatusWindow()
            let outputText = String(data: outputData, encoding: .utf8) ?? "<non UTF-8 output>"
            showErrorWindow("Failed to decode Lenslet JSON.\n\n\(error.localizedDescription)\n\nOutput:\n\(outputText)\n\nPython stderr:\n\(errorText.isEmpty ? "No stderr output." : errorText)")
        }
    }

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

        guard process.terminationStatus == 0 else {
            return false
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return false
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0 else {
            return false
        }

        return true
    }

    func showStatusWindow(_ message: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showStatusWindow(message)
            }
            return
        }

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
                ProgressView()
                    .controlSize(.large)

                Text(message)
                    .font(.headline)

                Text("OCR, summary, and memory search are running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 320, height: 140)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        runtime.statusWindow = window
    }

    func closeStatusWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                closeStatusWindow()
            }
            return
        }

        runtime.statusWindow?.orderOut(nil)
    }

    func showErrorWindow(_ message: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showErrorWindow(message)
            }
            return
        }

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

    func showResultWindow(_ result: LensletResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showResultWindow(result)
            }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        runtime.resultWindow?.orderOut(nil)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        window.center()
        window.title = "Lenslet"
        window.contentView = NSHostingView(
            rootView: ResultView(result: result)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        runtime.resultWindow = window
    }

    func showMemoryBrowserWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showMemoryBrowserWindow()
            }
            return
        }

        if let existingWindow = runtime.memoryBrowserWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        window.center()
        window.title = "Lenslet Memories"
        window.contentView = NSHostingView(
            rootView: MemoryBrowserView()
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        runtime.memoryBrowserWindow = window
    }
}
