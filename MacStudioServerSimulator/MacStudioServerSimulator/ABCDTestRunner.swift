//
//  ABCDTestRunner.swift
//  MacStudioServerSimulator
//
//  Test runner for ABCD performance tests
//

import Foundation
import SwiftUI

enum ABCDTestType: String, CaseIterable {
    case testA = "a"
    case testB = "b"
    case testC = "c"
    case testD = "d"
    
    var name: String {
        switch self {
        case .testA: return "Test A"
        case .testB: return "Test B"
        case .testC: return "Test C"
        case .testD: return "Test D"
        }
    }
    
    var expectedDuration: Double {
        switch self {
        case .testA: return 10.0
        case .testB: return 60.0
        case .testC: return 20.0
        case .testD: return 120.0
        }
    }
}

struct ABCDTestResult {
    let testType: ABCDTestType
    let passed: Bool
    let duration: Double
    let successCount: Int
    let totalCount: Int
    let timestamp: Date
    let output: String
    let analysisResults: [AnalysisResult]
}

@MainActor
class ABCDTestRunner: ObservableObject {
    @Published var isRunning = false
    @Published var currentTest: ABCDTestType?
    @Published var results: [ABCDTestType: ABCDTestResult] = [:]
    @Published var outputLines: [String] = []
    
    private let projectPath: String
    
    init() {
        // Get project path - need to go to EssentiaServer root
        // When running from Xcode or built app, we need to find the git repo root
        
        var path = ""
        
        // Try to find the EssentiaServer directory
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            // From app bundle, go up to find EssentiaServer
            var searchPath = bundlePath as String
            
            // Keep going up directories until we find run_test.sh or hit root
            for _ in 0..<10 {
                let testScriptPath = (searchPath as NSString).appendingPathComponent("run_test.sh")
                if FileManager.default.fileExists(atPath: testScriptPath) {
                    path = searchPath
                    break
                }
                searchPath = (searchPath as NSString).deletingLastPathComponent
            }
            
            // If we didn't find it, try going up from bundle to MacStudioServerSimulator then up one more
            if path.isEmpty || path == "/" {
                // Typical debug path: .../DerivedData/.../MacStudioServerSimulator.app
                // We want to go up to find the repo root
                var current = bundlePath.deletingLastPathComponent // Remove .app
                current = (current as NSString).deletingLastPathComponent // Remove Debug/Release
                current = (current as NSString).deletingLastPathComponent // Remove Products
                current = (current as NSString).deletingLastPathComponent // Remove Build
                current = (current as NSString).deletingLastPathComponent // Remove DerivedData dir
                
                // Now try to find EssentiaServer
                let documentsPath = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
                if FileManager.default.fileExists(atPath: documentsPath + "/run_test.sh") {
                    path = documentsPath
                } else {
                    path = current
                }
            }
        } else {
            // Fallback to hardcoded path
            path = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
        }
        
        self.projectPath = path
        
        addOutput("Test Runner initialized")
        addOutput("Project path: \(projectPath)")
        
        // Verify the path is correct
        let scriptPath = (projectPath as NSString).appendingPathComponent("run_test.sh")
        if FileManager.default.fileExists(atPath: scriptPath) {
            addOutput("✅ Found run_test.sh at: \(scriptPath)")
            addOutput("ℹ️  Tests will manage their own server instance")
        } else {
            addOutput("⚠️ Warning: run_test.sh not found at: \(scriptPath)")
            addOutput("Tests may not work correctly")
        }
    }
    
    func runTest(_ test: ABCDTestType) async {
        isRunning = true
        currentTest = test
        
        addOutput("\n" + String(repeating: "=", count: 60))
        addOutput("🧪 Running \(test.name)...")
        addOutput(String(repeating: "=", count: 60))
        
        let startTime = Date()
        
        // Use run_test.sh which manages its own server
        // This is more reliable than using the GUI-managed server
        let scriptPath = "\(projectPath)/run_test.sh"
        let output = await runCommand(scriptPath, arguments: [test.rawValue])
        
        let duration = Date().timeIntervalSince(startTime)
        
        addOutput("📝 Raw output length: \(output.count) characters")
        addOutput("📝 Output preview: \(output.prefix(200))")
        
        // Parse output
        let lines = output.components(separatedBy: "\n")
        addOutput("📝 Total lines: \(lines.count)")
        
        for line in lines {
            addOutput(line)
        }
        
        // Determine success
        let passed = output.contains("✅ Test completed successfully") ||
                    output.contains("All tests passed")
        
        addOutput("📝 Test passed: \(passed)")
        
        // Extract success count, CSV path, and analysis rows
        var successCount = 0
        var totalCount = 0
        var analysisResults: [AnalysisResult] = []
        var csvPath: String?
        
        for line in lines {
            let cleanLine = stripANSICodes(from: line)
            
            if cleanLine.contains("Successful:") || cleanLine.contains("successful") {
                if let range = cleanLine.range(of: #"(\d+)/(\d+)"#, options: .regularExpression) {
                    let numbers = cleanLine[range].split(separator: "/")
                    if numbers.count == 2 {
                        successCount = Int(numbers[0]) ?? 0
                        totalCount = Int(numbers[1]) ?? 0
                    }
                }
            }
            
            if cleanLine.contains("Results saved to:") {
                if let path = cleanLine.components(separatedBy: "Results saved to:").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    csvPath = path
                    addOutput("📁 Detected CSV output: \(path)")
                }
            }
        }
        
        if let path = csvPath {
            let csvResults = loadAnalysisResults(fromCSV: path)
            if !csvResults.isEmpty {
                analysisResults = csvResults
                addOutput("📊 Loaded \(csvResults.count) analysis rows from CSV")
            } else {
                addOutput("⚠️ Failed to read analysis rows from CSV at \(path)")
            }
        }
        
        if analysisResults.isEmpty {
            analysisResults = extractAnalysisResults(from: output)
            addOutput("🧾 Parsed \(analysisResults.count) analysis rows from console output")
        }
        
        addOutput("📊 Total analysis results parsed: \(analysisResults.count)")
        
        // Default counts if not found
        if totalCount == 0 {
            totalCount = (test == .testA || test == .testB) ? 6 : 12
            successCount = passed ? totalCount : 0
        }
        
        // Store result
        results[test] = ABCDTestResult(
            testType: test,
            passed: passed,
            duration: duration,
            successCount: successCount,
            totalCount: totalCount,
            timestamp: Date(),
            output: output,
            analysisResults: analysisResults
        )
        
        if passed {
            addOutput("✅ \(test.name) completed in \(String(format: "%.2f", duration))s")
        } else {
            addOutput("❌ \(test.name) failed")
        }
        
        isRunning = false
        currentTest = nil
    }
    
    private func stripANSICodes(from text: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*m"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    
    private func extractAnalysisResults(from output: String) -> [AnalysisResult] {
        let cleanOutput = stripANSICodes(from: output).replacingOccurrences(of: "\r", with: "\n")
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*\d+\.\s+(.+?)\s+\|\s+BPM:\s*([\d.]+|N/A)\s+\|\s+Key:\s*([^|]+?)\s+\|"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(cleanOutput.startIndex..<cleanOutput.endIndex, in: cleanOutput)
        var results: [AnalysisResult] = []
        regex.enumerateMatches(in: cleanOutput, options: [], range: range) { match, _, _ in
        guard let match = match,
            let songRange = Range(match.range(at: 1), in: cleanOutput),
                  let bpmRange = Range(match.range(at: 2), in: cleanOutput),
                  let keyRange = Range(match.range(at: 3), in: cleanOutput) else { return }
        let rawSong = String(cleanOutput[songRange]).trimmingCharacters(in: .whitespaces)
        let song = cleanSongTitle(rawSong)
            let bpmString = String(cleanOutput[bpmRange]).trimmingCharacters(in: .whitespaces)
            let keyString = String(cleanOutput[keyRange]).trimmingCharacters(in: .whitespaces)
            let bpmValue: Int? = {
                if let bpmDouble = Double(bpmString) {
                    return Int(round(bpmDouble))
                }
                return nil
            }()
            let keyValue = keyString.isEmpty || keyString == "N/A" ? nil : keyString
            let result = AnalysisResult(
                song: song,
                artist: "Unknown",
                bpm: bpmValue,
                key: keyValue,
                success: true,
                duration: 0
            )
            results.append(result)
        }
        return results
    }
    
    private func loadAnalysisResults(fromCSV csvPath: String) -> [AnalysisResult] {
        var resolvedPath = csvPath
        if !resolvedPath.hasPrefix("/") {
            resolvedPath = (projectPath as NSString).appendingPathComponent(csvPath)
        }
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return []
        }
        guard let csvString = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            return []
        }
        let rows = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard rows.count > 1 else {
            return []
        }
        var results: [AnalysisResult] = []
        for row in rows.dropFirst() {
            let columns = parseCSVRow(row)
            guard columns.count >= 10 else { continue }
            let rawSong = columns[1].replacingOccurrences(of: "\"", with: "")
            let song = cleanSongTitle(rawSong)
            let artist = columns[2].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            let successValue = columns[4].lowercased()
            let success = successValue == "true" || successValue == "1" || successValue == "yes"
            let duration = Double(columns[5]) ?? 0
            let bpmValue: Int? = {
                if let bpmDouble = Double(columns[6]) {
                    return Int(round(bpmDouble))
                }
                return nil
            }()
            let keyValue = columns[7].trimmingCharacters(in: .whitespaces)
            let key = keyValue.isEmpty ? nil : keyValue
            let result = AnalysisResult(
                song: song,
                artist: artist,
                bpm: bpmValue,
                key: key,
                success: success,
                duration: duration
            )
            results.append(result)
        }
        return results
    }
    
    private func cleanSongTitle(_ raw: String) -> String {
        SongTitleNormalizer.clean(raw)
    }
    
    private func parseCSVRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
                continue
            }
            if char == "," && !insideQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)
        return columns
    }
    
    func runAllTests() async {
        for test in ABCDTestType.allCases {
            await runTest(test)
            if test != .testD {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second pause
            }
        }
        
        addOutput("\n" + String(repeating: "=", count: 60))
        addOutput("🎉 All tests completed!")
        addOutput(String(repeating: "=", count: 60))
        
        // Summary
        var allPassed = true
        for test in ABCDTestType.allCases {
            if let result = results[test] {
                let status = result.passed ? "✅ PASSED" : "❌ FAILED"
                addOutput("\(test.name): \(status) (\(String(format: "%.2f", result.duration))s)")
                if !result.passed {
                    allPassed = false
                }
            }
        }
        
        if allPassed {
            addOutput("\n🎊 All tests passed!")
        } else {
            addOutput("\n⚠️ Some tests failed")
        }
    }
    
    private func runCommand(_ command: String, arguments: [String]) async -> String {
        return await withCheckedContinuation { continuation in
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
