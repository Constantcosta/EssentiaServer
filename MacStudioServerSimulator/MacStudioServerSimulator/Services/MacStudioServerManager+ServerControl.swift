import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private let serverControlLogger = Logger(subsystem: "com.macstudio.serverapp", category: "ServerControl")
#endif

extension MacStudioServerManager {
// MARK: - Server Control
    // Note: iOS apps cannot launch external processes
    // The Python server must be started manually on the Mac Studio
    
    /// Start the analyzer process.
    /// - Parameter skipPreflight: When true, skips health/shutdown checks for a cleaner restart
    ///   (used by batch restarts where we already stopped the server).
    func startServer(skipPreflight: Bool = false) async {
        userStoppedServer = false
        #if os(macOS)
        guard serverProcess?.isRunning != true else {
            await checkServerStatus()
            return
        }
        
        isLoading = true
        errorMessage = nil
        let scriptURL = serverScriptURL
        
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            errorMessage = """
            Could not find analyze_server.py at \(scriptURL.path).
            Update the path via:
            defaults write com.macstudio.serversimulator MacStudioServerScriptPath /path/to/analyze_server.py
            """
            isLoading = false
            return
        }

        if !skipPreflight {
            // Ensure we are not leaving an older Python build running in the background,
            // otherwise we keep talking to stale code and hit _GeneratorContextManager errors.
            await shutdownExistingServerIfNeeded()
        }
        
        let pythonURL: URL
        do {
            pythonURL = try resolvePythonExecutableURL()
        } catch {
            errorMessage = pythonResolutionErrorMessage(for: error)
            isLoading = false
            return
        }
        
        appendLaunchConfirmationToServerLog(pythonPath: pythonURL.path)
        
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path]
        // Run from repo root, not backend/ - the server imports 'backend' as a package
        let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        process.currentDirectoryURL = repoRoot
        
        // Set PYTHONPATH to repo root so Python can find the backend package
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = repoRoot.path
        environment["PYTHONUNBUFFERED"] = "1"
        // Opt into preview-friendly defaults regardless of user shell/.env so GUI runs stay fast.
        environment["ANALYSIS_WORKERS"] = "6"            // match GUI concurrency
        environment["MAX_ANALYSIS_SECONDS"] = "30"       // cap per clip (previews)
        environment["ANALYSIS_SAMPLE_RATE"] = "12000"    // lighter preview profile
        environment["CHUNK_ANALYSIS_SECONDS"] = "15"     // keep chunking but lighter
        environment["CHUNK_OVERLAP_SECONDS"] = "5"
        environment["MIN_CHUNK_DURATION_SECONDS"] = "5"
        // Clear log on startup
        environment["CLEAR_LOG"] = "1"
        process.environment = environment
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                self.serverProcess = nil
                if proc.terminationStatus != 0 && self.errorMessage == nil {
                    self.errorMessage = "Server exited with status \(proc.terminationStatus)"
                }
                await self.checkServerStatus()
            }
        }
        
        do {
            #if os(macOS)
            serverControlLogger.info("Launching analyzer via \(process.executableURL?.path ?? "unknown", privacy: .public)")
            if let pythonPath = process.environment?["PYTHONPATH"] {
                serverControlLogger.debug("PYTHONPATH=\(pythonPath, privacy: .public)")
            }
            #endif
            try process.run()
            serverProcess = process
            try? await Task.sleep(for: .seconds(1.5))
            await checkServerStatus()
#if os(macOS)
            if isServerRunning {
                rememberCurrentAnalyzerSignature()
            }
#endif
        } catch {
            errorMessage = "Failed to start server: \(error.localizedDescription)"
            serverProcess = nil
        }
        
        isLoading = false
        #else
        isLoading = true
        errorMessage = "⚠️ iOS apps cannot start external servers.\n\nPlease start the server manually on your Mac Studio:\n\n1. Open Terminal on Mac Studio\n2. cd ~/Documents/Git\\ repo/Songwise\\ 1/mac-studio-server/\n3. python3 analyze_server.py\n\nThen tap 'Check Status' to verify connection."
        isLoading = false
        await checkServerStatus()
        #endif
    }
    
    func stopServer(userTriggered: Bool = true) async {
        if userTriggered {
            userStoppedServer = true
        }
        isLoading = true
        errorMessage = nil
        
        // Try to shutdown via API
        do {
            guard let url = URL(string: "\(baseURL)/shutdown") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            
            let (_, _) = try await URLSession.shared.data(for: request)
            isServerRunning = false
        } catch {
            errorMessage = "Failed to stop server: \(error.localizedDescription)"
        }
        
        #if os(macOS)
        // Kill the process we started
        if serverProcess?.isRunning == true {
            serverProcess?.terminate()
        }
        serverProcess = nil
        
        // Also kill any external analyze_server.py processes on our port
        // This handles cases where server was started outside the GUI
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-f", "analyze_server.py"]
        try? killProcess.run()
        killProcess.waitUntilExit()
        
        // Give processes time to shut down
        try? await Task.sleep(for: .seconds(0.5))
        #endif
        
        isLoading = false
    }
    
    func restartServer() async {
        await stopServer(userTriggered: false)
        try? await Task.sleep(for: .seconds(1))
        // On restart we already issued /shutdown and cleaned up processes,
        // so skip the extra /health preflight to avoid noisy connection errors.
        await startServer(skipPreflight: true)
    }

    func autoStartServerIfNeeded(autoManageEnabled: Bool, overrideUserStop: Bool = false) async {
        guard autoManageEnabled else {
            recordAutoManageDisabled()
            return
        }
        
        await checkServerStatus()
        
        if userStoppedServer && !overrideUserStop {
            publishAutoManageBanner(
                "Auto-manage paused because you manually stopped the analyzer.",
                kind: .warning
            )
            return
        }
        
        guard !isServerRunning else {
            autoManageBanner = nil
            return
        }
        
        guard !isLoading else {
            publishAutoManageBanner(
                "Analyzer is busy — auto-manage will retry shortly.",
                kind: .info
            )
            return
        }
        
        publishAutoManageBanner(
            "Auto-manage is starting the local analyzer…",
            kind: .info
        )
        
        await startServer()
        
        if isServerRunning {
            publishAutoManageBanner(
                "Analyzer launched automatically.",
                kind: .success
            )
        } else {
            publishAutoManageBanner(
                "Automatic launch failed — check the log for details.",
                kind: .error
            )
        }
    }

    func publishAutoManageBanner(_ message: String, kind: AutoManageBanner.Kind) {
        autoManageBanner = AutoManageBanner(message: message, kind: kind, timestamp: Date())
    }
    
    func recordAutoManageDisabled() {
        publishAutoManageBanner(
            "Auto-manage is off — start the analyzer manually when you're ready.",
            kind: .warning
        )
    }
    
    


// MARK: - Server Status
    
    func checkServerStatus() async {
        do {
            guard let url = URL(string: "\(baseURL)/health") else { return }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            let status = try JSONDecoder().decode(ServerStatus.self, from: data)
            isServerRunning = status.running
        } catch {
            isServerRunning = false
        }
    }
    
    


// MARK: - Statistics
    
    func fetchServerStats(silently: Bool = false) async {
        if !silently {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            guard let url = URL(string: "\(baseURL)/stats") else { return }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            serverStats = try JSONDecoder().decode(ServerStats.self, from: data)
            if !silently {
                isLoading = false
            }
        } catch {
            if !silently {
                errorMessage = "Failed to fetch stats: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

}
