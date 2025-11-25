//
//  ABCDTestRunner+Command.swift
//  MacStudioServerSimulator
//
//  Shell execution and logging helpers for ABCD tests.
//

import Foundation

@MainActor
extension ABCDTestRunner {
    func runCommand(_ command: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            
            // Set up environment to ensure script can find python and venv
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(projectPath)/.venv/bin"
            environment["VIRTUAL_ENV"] = "\(projectPath)/.venv"
            process.environment = environment
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            addOutput("🔧 Executing: \(command) \(arguments.joined(separator: " "))")
            addOutput("🔧 Working directory: \(projectPath)")
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let exitCode = process.terminationStatus
                addOutput("🔧 Exit code: \(exitCode)")
                
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                let errorMsg = "Error: \(error.localizedDescription)"
                addOutput("❌ \(errorMsg)")
                continuation.resume(returning: errorMsg)
            }
        }
    }
    
    func addOutput(_ line: String) {
        outputLines.append(line)
        
        // Keep only last 1000 lines
        if outputLines.count > 1000 {
            outputLines.removeFirst(outputLines.count - 1000)
        }
    }
    
    func clearOutput() {
        outputLines.removeAll()
        addOutput("Output cleared")
    }
}
