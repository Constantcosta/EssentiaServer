import Foundation

#if os(macOS)
private struct DiagnosticScript: Identifiable {
    let id = UUID()
    let name: String
    let scriptPath: String
    let requiresServer: Bool
}
#endif

extension MacStudioServerManager {
    func runDiagnosticsSuite() async {
        guard !isRunningDiagnostics else { return }
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: repoRootURL.path) else {
            diagnosticsErrorMessage = "Repository folder not found at \(repoRootURL.path)"
            diagnosticsPassed = false
            return
        }
        
        isRunningDiagnostics = true
        diagnosticsErrorMessage = nil
        diagnosticsPassed = nil
        diagnosticsLastRun = Date()
        diagnosticsLog = "🧪 Starting diagnostics at \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n\n"
        
        let scripts: [DiagnosticScript] = [
            DiagnosticScript(
                name: "Server Health & Component Status",
                scriptPath: "", // Special: will use HTTP endpoint instead
                requiresServer: true
            ),
            DiagnosticScript(
                name: "Essentia Workers Verification",
                scriptPath: repoRootURL.appendingPathComponent("tools/verify_essentia_workers.py").path,
                requiresServer: false
            ),
            DiagnosticScript(
                name: "Phase 1 Feature Tests",
                scriptPath: repoRootURL.appendingPathComponent("backend/test_phase1_features.py").path,
                requiresServer: false
            ),
            DiagnosticScript(
                name: "Server Endpoint Smoke Test",
                scriptPath: repoRootURL.appendingPathComponent("backend/test_server.py").path,
                requiresServer: true
            ),
            DiagnosticScript(
                name: "Performance Benchmarks",
                scriptPath: repoRootURL.appendingPathComponent("backend/performance_test.py").path,
                requiresServer: false
            )
        ]
        
        var overallSuccess = true
        
        for script in scripts {
            if script.requiresServer && !isServerRunning {
                diagnosticsLog.append("⚠️ \(script.name) skipped — start the analyzer first.\n\n")
                overallSuccess = false
                continue
            }
            
            diagnosticsLog.append("▶️ Running \(script.name)…\n")
            
            // Special case: Server Health & Component Status uses HTTP endpoint
            if script.name == "Server Health & Component Status" {
                do {
                    let diagnosticsData = try await fetchServerDiagnostics()
                    diagnosticsLog.append(formatDiagnosticsOutput(diagnosticsData))
                    diagnosticsLog.append("\n✅ \(script.name) completed.\n\n")
                } catch {
                    diagnosticsLog.append("❌ Could not fetch server diagnostics: \(error.localizedDescription)\n\n")
                    overallSuccess = false
                }
                continue
            }
            
            do {
                let (status, output) = try await executeDiagnosticScript(at: script.scriptPath)
                diagnosticsLog.append(output)
                diagnosticsLog.append("\n")
                if status == 0 {
                    diagnosticsLog.append("✅ \(script.name) passed.\n\n")
                } else {
                    diagnosticsLog.append("❌ \(script.name) failed (exit code \(status)).\n\n")
                    overallSuccess = false
                }
            } catch {
                diagnosticsLog.append("❌ \(script.name) could not run: \(error.localizedDescription)\n\n")
                diagnosticsErrorMessage = error.localizedDescription
                overallSuccess = false
            }
        }
        
        diagnosticsPassed = overallSuccess
        diagnosticsLastRun = Date()
        diagnosticsLog.append("🏁 Diagnostics finished.\n")
        isRunningDiagnostics = false
        #else
        diagnosticsErrorMessage = "Diagnostics can only run on macOS."
        diagnosticsPassed = false
        #endif
    }
    
    #if os(macOS)
    private func fetchServerDiagnostics() async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/diagnostics") else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        return json
    }
    
    private func formatDiagnosticsOutput(_ data: [String: Any]) -> String {
        var output = ""
        
        // Overall status
        if let status = data["overall_status"] as? String {
            let emoji = status == "healthy" ? "✅" : status == "degraded" ? "⚠️" : "❌"
            output += "\(emoji) Overall Status: \(status.uppercased())\n\n"
        }
        
        // Build info
        if let build = data["build"] as? String {
            output += "Build: \(build)\n"
        }
        if let mode = data["mode"] as? String {
            output += "Mode: \(mode)\n"
        }
        output += "\n"
        
        // Components
        if let components = data["components"] as? [String: [String: Any]] {
            output += "Components:\n"
            for (name, info) in components.sorted(by: { $0.key < $1.key }) {
                if let status = info["status"] as? String {
                    let emoji = status == "operational" ? "✅" : status == "degraded" ? "⚠️" : "❌"
                    output += "  \(emoji) \(name.capitalized): \(status)\n"
                    
                    // Add specific details
                    if name == "calibration" {
                        if let scalerCount = info["scaler_count"] as? Int {
                            output += "     - Scalers: \(scalerCount) loaded\n"
                        }
                        if let modelCount = info["model_count"] as? Int {
                            output += "     - Models: \(modelCount) loaded\n"
                        }
                        if let keyCount = info["key_rule_count"] as? Int {
                            output += "     - Key rules: \(keyCount) loaded\n"
                        }
                    } else if name == "database" {
                        if let entries = info["cache_entries"] as? Int {
                            output += "     - Cache entries: \(entries)\n"
                        }
                        if let analyses = info["total_analyses"] as? Int {
                            output += "     - Total analyses: \(analyses)\n"
                        }
                    }
                }
            }
            output += "\n"
        }
        
        // Warnings
        if let warnings = data["warnings"] as? [String], !warnings.isEmpty {
            output += "Warnings:\n"
            for warning in warnings {
                output += "  ⚠️ \(warning)\n"
            }
            output += "\n"
        }
        
        // Configuration highlights with architecture mode detection
        if let config = data["configuration"] as? [String: Any] {
            if let analysis = config["analysis"] as? [String: Any] {
                output += "Analysis Configuration:\n"
                
                // Determine architecture mode based on settings
                let sampleRate = analysis["sample_rate"] as? Int ?? 12000
                let chunkSeconds = analysis["chunk_seconds"] as? Int ?? 15
                let maxDuration = analysis["max_duration"] as? Int
                
                let isFullSongMode = sampleRate >= 22050 && chunkSeconds >= 25 && (maxDuration == nil || maxDuration == 0)
                let isPreviewMode = sampleRate <= 12000 && chunkSeconds <= 20 && maxDuration != nil && maxDuration! <= 30
                
                if isFullSongMode {
                    output += "  🎵 Mode: FULL-SONG OPTIMIZED (Calibration)\n"
                } else if isPreviewMode {
                    output += "  ⚡ Mode: PREVIEW OPTIMIZED (30s clips)\n"
                } else {
                    output += "  ⚙️ Mode: CUSTOM\n"
                }
                
                if let workers = analysis["workers"] as? Int {
                    let emoji = workers >= 6 ? "🔥" : workers >= 4 ? "✅" : "⚠️"
                    output += "  \(emoji) Workers: \(workers) parallel"
                    if workers < 4 {
                        output += " (consider 6-8 for M4 Max)"
                    }
                    output += "\n"
                }
                
                if let sampleRate = analysis["sample_rate"] as? Int {
                    let quality = sampleRate >= 22050 ? "High" : sampleRate >= 16000 ? "Medium" : "Basic"
                    output += "  - Sample rate: \(sampleRate) Hz (\(quality) quality)\n"
                }
                
                if let chunkSeconds = analysis["chunk_seconds"] as? Int {
                    output += "  - Chunk size: \(chunkSeconds)s"
                    if isFullSongMode && chunkSeconds < 30 {
                        output += " (consider 30s for full songs)"
                    }
                    output += "\n"
                }
                
                if let maxChunks = analysis["max_chunks"] as? Int {
                    output += "  - Max chunks: \(maxChunks) per song\n"
                }
                
                if let fftSize = analysis["fft_size"] as? Int {
                    output += "  - FFT size: \(fftSize)\n"
                }
                
                if let maxDuration = maxDuration {
                    if maxDuration == 0 {
                        output += "  - Duration limit: None (full songs)\n"
                    } else {
                        output += "  - Duration limit: \(maxDuration)s\n"
                    }
                }
                
                output += "\n"
                
                // Performance estimate
                if isFullSongMode {
                    output += "Performance Estimate (12 songs, ~3.5 min each):\n"
                    let workersCount = analysis["workers"] as? Int ?? 2
                    let estimatedTime = (12 * 35) / workersCount  // ~35s per song
                    output += "  ⏱️ ~\(estimatedTime)s total (~\(estimatedTime/12)s per song average)\n"
                    output += "  💡 Optimized for calibration quality\n\n"
                } else if isPreviewMode {
                    output += "Performance Estimate (30s previews):\n"
                    output += "  ⏱️ ~3-5s per preview\n"
                    output += "  💡 Optimized for speed\n\n"
                }
            }
        }
        
        return output
    }
    
    private func executeDiagnosticScript(at path: String) async throws -> (Int32, String) {
        let pythonURL = try resolvePythonExecutableURL()
        let workingDirectory = repoRootURL
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["MAC_STUDIO_SERVER_PORT"] = "\(serverPort)"
        environment["MAC_STUDIO_SERVER_HOST"] = "127.0.0.1"
        environment["TEST_SERVER_URL"] = baseURL
        environment["TEST_ANALYZE_ACCEPTABLE_STATUS"] = "200,500,502"
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let process = Process()
                    process.executableURL = pythonURL
                    process.arguments = [path]
                    process.currentDirectoryURL = workingDirectory
                    process.environment = environment
                    
                    let outputPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = outputPipe
                    
                    try process.run()
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (process.terminationStatus, output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #endif
}
