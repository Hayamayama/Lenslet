import SwiftUI
import AppKit

@main
struct LensletApp: App {
    
    var body: some Scene {
        
        MenuBarExtra(
            "Lenslet",
            systemImage: "eye"
        ) {
            
            Button("Capture") {
                runLenslet()
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
        
        let process = Process()
        process.executableURL = pythonURL
        process.currentDirectoryURL = projectURL
        process.arguments = ["main.py"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print(text)
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print(text)
            }
        }
        
        do {
            try process.run()
        } catch {
            print("Failed to run Lenslet Python core:", error)
        }
    }
}
