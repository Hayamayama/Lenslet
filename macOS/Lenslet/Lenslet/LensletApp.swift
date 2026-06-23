import SwiftUI
import AppKit

@main
struct LensletApp: App {
    @State private var latestResult: LensletResult?
    @State private var resultWindow: NSWindow?
    @State private var currentProcess: Process?
    
    var body: some Scene {
        
        MenuBarExtra(
            "Lenslet",
            systemImage: "eye"
        ) {
            
            Button("Capture") {
                runLenslet()
            }
            
            Button("Show Result") {
                if let result = latestResult {
                    showResultWindow(result)
                }
            }
            
            Divider()
            
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    
    func runLenslet() {
        let projectURL = URL(
            fileURLWithPath: "/Users/kris/Documents/04_Research_Dev/VSC/Lenslet"
        )
        
        let pythonURL = projectURL
            .appendingPathComponent(".venv/bin/python")

        let captureURL = URL(fileURLWithPath: "/tmp/lenslet_capture.png")
        
        guard captureScreen(to: captureURL) else {
            print("Lenslet capture cancelled or failed.")
            return
        }
        
        let resultURL = URL(fileURLWithPath: "/tmp/lenslet_result.json")
        let errorURL = URL(fileURLWithPath: "/tmp/lenslet_error.log")
        
        FileManager.default.createFile(
            atPath: resultURL.path,
            contents: nil
        )
        FileManager.default.createFile(
            atPath: errorURL.path,
            contents: nil
        )
        
        guard let resultHandle = try? FileHandle(forWritingTo: resultURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            print("Failed to create Lenslet output files.")
            return
        }
        
        let process = Process()
        currentProcess = process
        process.executableURL = pythonURL
        process.currentDirectoryURL = projectURL
        process.arguments = [
            "main.py",
            "--json",
            "--image",
            captureURL.path
        ]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        process.standardOutput = resultHandle
        process.standardError = errorHandle
        
        process.terminationHandler = { _ in
            resultHandle.closeFile()
            errorHandle.closeFile()
            
            if let errorText = try? String(contentsOf: errorURL, encoding: .utf8), !errorText.isEmpty {
                print(errorText)
            }
            
            guard let outputData = try? Data(contentsOf: resultURL), !outputData.isEmpty else {
                print("Lenslet returned no output.")
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
                
                DispatchQueue.main.async {
                    latestResult = decoded
                    showResultWindow(decoded)
                    currentProcess = nil
                }
            } catch {
                print("Failed to decode Lenslet JSON:", error)
            }
        }
        
        do {
            try process.run()
        } catch {
            print("Failed to run Lenslet Python core:", error)
            currentProcess = nil
        }
    }

    func captureScreen(to outputURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-i",
            outputURL.path
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to run screencapture:", error)
            return false
        }
        
        return process.terminationStatus == 0
    }
    
    func showResultWindow(_ result: LensletResult) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "Lenslet"
        window.contentView = NSHostingView(
            rootView: ResultView(result: result)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        resultWindow = window
    }
}
