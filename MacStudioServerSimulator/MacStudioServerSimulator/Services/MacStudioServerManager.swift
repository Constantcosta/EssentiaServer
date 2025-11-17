//
//  MacStudioServerManager.swift
//  repapp
//
//  Created on 29/10/2025.
//  Shared client for the Mac Studio Audio Analysis Server.
//  macOS builds can launch/stop the Python service locally, while iOS
//  builds simply monitor and call the HTTP API.
//

import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

// SUMMARY
// ObservableObject client for the external Mac Studio audio-analysis server.
// Tracks server status/cache, wraps REST endpoints (health, stats, cache ops),
// and reminds users to manually run the Python service.

@MainActor
class MacStudioServerManager: ObservableObject {
    
    private static let authorizedFolderBookmarkKey = "MacStudioAuthorizedFolderBookmark"
    private static var authorizedFolderURL: URL?
    private static var authorizedFolderAccessActive = false
    
    // MARK: - Published Properties
    
    @Published var isServerRunning = false
    @Published var serverStats: ServerStats?
    @Published var cachedAnalyses: [CachedAnalysis] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var serverPort = 5050
    @Published var quickAnalyzeErrors: [DropErrorEntry] = []
    @Published var quickAnalyzeHistory: [QuickAnalyzeResultEntry] = []
    @Published var authorizedFolderDisplayName: String?
    @Published var autoManageBanner: AutoManageBanner?
    @Published var calibrationSongs: [CalibrationSong] = []
    @Published var calibrationLog: [String] = []
    @Published var isCalibrationRunning = false
    @Published var calibrationProgress: Double = 0
    @Published var calibrationError: String?
    @Published var lastCalibrationOutputURL: URL?
    @Published var lastCalibrationExportURL: URL?
    @Published var lastCalibrationComparison: String?
    @Published var lastCalibrationComparisonURL: URL?
    @Published var isResettingCalibration = false
    @Published var isComparingCalibration = false
    @Published var isRunningDiagnostics = false
    @Published var diagnosticsLog: String = ""
    @Published var diagnosticsLastRun: Date?
    @Published var diagnosticsPassed: Bool?
    @Published var diagnosticsErrorMessage: String?
    
#if os(macOS)
    private let analyzerCodeSignatureKey = "MacStudioServerLastCodeSignature"
    private var analyzerCodeMonitorTask: Task<Void, Never>?
#endif
    
    init() {
        restoreAuthorizedFolderAccess()
        loadCalibrationSongsFromDisk()
        restoreLastCalibrationOutputFromDisk()
        restoreLastCalibrationExportFromDisk()
#if os(macOS)
        startAnalyzerCodeMonitor()
#endif
    }
    
#if os(macOS)
    deinit {
        analyzerCodeMonitorTask?.cancel()
    }
#endif
    
    // MARK: - Constants & Mac helpers
    
    let apiKey = "8sxO1R8TM3Jv9AVyzbh-Kej0xYKrHWj87CLHRTufHv0"
    private let maxCalibrationSongs = 57
    
    lazy var calibrationTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    lazy var calibrationFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    let supportedAudioExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "flac", "aac", "caf"]
    
    #if os(macOS)
    var serverProcess: Process?
    var userStoppedServer = false
    
    var serverScriptURL: URL {
        if let override = UserDefaults.standard.string(forKey: "MacStudioServerScriptPath"),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GitHub/EssentiaServer/backend/analyze_server.py")
    }
    #endif
    
#if os(macOS)
    private func startAnalyzerCodeMonitor() {
        analyzerCodeMonitorTask?.cancel()
        analyzerCodeMonitorTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self.checkForAnalyzerCodeUpdate()
            }
        }
    }
    
    @MainActor
    private func checkForAnalyzerCodeUpdate() async {
        guard !isLoading else { return }
        guard !userStoppedServer else { return }
        guard let signature = await fetchAnalyzerCodeSignature() else { return }
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: analyzerCodeSignatureKey)
        if previous == nil {
            defaults.set(signature, forKey: analyzerCodeSignatureKey)
            return
        }
        guard previous != signature else { return }
        guard isServerRunning else {
            defaults.set(signature, forKey: analyzerCodeSignatureKey)
            return
        }
        publishAutoManageBanner(
            "Detected new analyzer build (\(signature.prefix(7))) — restarting…",
            kind: .info
        )
        await restartServer()
        defaults.set(signature, forKey: analyzerCodeSignatureKey)
    }
    
    private func fetchAnalyzerCodeSignature() async -> String? {
        computeAnalyzerCodeSignature()
    }
    
    private func computeAnalyzerCodeSignature() -> String? {
        let scriptURL = serverScriptURL
        let backendDir = scriptURL.deletingLastPathComponent()
        let repoRoot = backendDir.deletingLastPathComponent()
        let gitDir = repoRoot.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = ["git", "-C", repoRoot.path, "rev-parse", "HEAD"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        return text
                    }
                }
            } catch {
                // Ignore and fall back to mtime.
            }
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: backendDir.path),
           let modified = attrs[.modificationDate] as? Date {
            return "mtime:\(modified.timeIntervalSince1970)"
        }
        return nil
    }
    
    func rememberCurrentAnalyzerSignature() {
        Task {
            if let signature = await fetchAnalyzerCodeSignature() {
                UserDefaults.standard.set(signature, forKey: analyzerCodeSignatureKey)
            }
        }
    }
#endif

    func shutdownExistingServerIfNeeded() async {
        guard let healthURL = URL(string: "\(baseURL)/health") else { return }
        var healthRequest = URLRequest(url: healthURL)
        healthRequest.timeoutInterval = 1.5
        healthRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        do {
            _ = try await URLSession.shared.data(for: healthRequest)
        } catch {
            // Nothing is listening, so no need to stop anything.
            // But still kill any orphaned Python processes (spawn workers, etc.)
            #if os(macOS)
            await killAllPythonProcesses()
            #endif
            return
        }

        guard let shutdownURL = URL(string: "\(baseURL)/shutdown") else { return }
        var shutdownRequest = URLRequest(url: shutdownURL)
        shutdownRequest.httpMethod = "POST"
        shutdownRequest.timeoutInterval = 2
        shutdownRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            _ = try await URLSession.shared.data(for: shutdownRequest)
            // Give the old process a moment to release the port.
            try? await Task.sleep(for: .seconds(1))
        } catch {
            // The legacy server might not support /shutdown; forcefully kill it.
            #if os(macOS)
            await killAllPythonProcesses()
            #endif
        }
        
        // Always do a final cleanup to ensure no spawn workers remain
        #if os(macOS)
        await killAllPythonProcesses()
        try? await Task.sleep(for: .seconds(1))
        #endif
    }
    
    #if os(macOS)
    private func killAllPythonProcesses() async {
        // Kill main server process
        let killServer = Process()
        killServer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killServer.arguments = ["-9", "-f", "analyze_server.py"]
        try? killServer.run()
        killServer.waitUntilExit()
        
        // Kill any multiprocessing spawn workers
        let killWorkers = Process()
        killWorkers.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killWorkers.arguments = ["-9", "-f", "multiprocessing.spawn"]
        try? killWorkers.run()
        killWorkers.waitUntilExit()
        
        // Kill any remaining Python processes from this repo
        let killPython = Process()
        killPython.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killPython.arguments = ["-9", "-f", "EssentiaServer.*Python"]
        try? killPython.run()
        killPython.waitUntilExit()
    }
    #endif
    
    var baseURL: String {
        #if os(macOS)
        return "http://127.0.0.1:\(serverPort)"
        #elseif targetEnvironment(simulator)
        return "http://127.0.0.1:\(serverPort)"
        #else
        return "http://Costass-Mac-Studio.local:\(serverPort)"
        #endif
    }

    // MARK: - Calibration Paths & Helpers
    
    func ensureDirectoryExists(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("MacStudioServerSimulator", isDirectory: true)
        ensureDirectoryExists(at: directory)
        return directory
    }
    
    var calibrationSongsDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("CalibrationSongs", isDirectory: true)
        ensureDirectoryExists(at: directory)
        return directory
    }
    
    var calibrationExportsDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("CalibrationExports", isDirectory: true)
        ensureDirectoryExists(at: directory)
        return directory
    }
    
    var calibrationSongsFolderPath: String {
        calibrationSongsDirectory.path
    }
    
    var calibrationExportsFolderPath: String {
        calibrationExportsDirectory.path
    }
    
    var calibrationSongLimit: Int { maxCalibrationSongs }
    
    var calibrationMetadataURL: URL {
        appSupportDirectory.appendingPathComponent("calibration_songs.json")
    }
    
    var repoRootURL: URL {
        serverScriptURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func restoreLastCalibrationOutputFromDisk() {
        let calibrationDir = repoRootURL.appendingPathComponent("data/calibration", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: calibrationDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        guard let latest = files
            .filter({ $0.pathExtension.lowercased() == "parquet" })
            .max(by: { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            }) else {
            return
        }
        lastCalibrationOutputURL = latest
    }

    private func restoreLastCalibrationExportFromDisk() {
        let exportsDir = calibrationExportsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: exportsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        lastCalibrationExportURL = files
            .filter { $0.pathExtension.lowercased() == "csv" }
            .max(by: { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            })
    }

    func makeComparisonReportURL(for datasetURL: URL) -> URL {
        let reportsDir = repoRootURL.appendingPathComponent("reports/calibration_reviews", isDirectory: true)
        ensureDirectoryExists(at: reportsDir)
        let baseName = datasetURL.deletingPathExtension().lastPathComponent
        return reportsDir.appendingPathComponent("\(baseName)_comparison.csv")
    }
    
    // MARK: - Folder Authorization
    
    #if os(macOS)
    func promptForAuthorizedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Authorize"
        panel.message = "Select the folder that contains the audio files you want to import."
        
        if panel.runModal() == .OK, let url = panel.url {
            setAuthorizedFolder(url)
        }
    }
    #endif
    
    private func setAuthorizedFolder(_ url: URL) {
        stopAuthorizedFolderAccess()
        
        do {
            var options: URL.BookmarkCreationOptions = [.withSecurityScope]
            if #available(macOS 13.0, *) {
                options.insert(.securityScopeAllowOnlyReadAccess)
            }
            let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.authorizedFolderBookmarkKey)
            Self.authorizedFolderURL = url
            Self.authorizedFolderAccessActive = url.startAccessingSecurityScopedResource()
            authorizedFolderDisplayName = url.lastPathComponent
        } catch {
            errorMessage = "Failed to save folder: \(error.localizedDescription)"
        }
    }
    
    private func stopAuthorizedFolderAccess() {
        if Self.authorizedFolderAccessActive {
            Self.authorizedFolderURL?.stopAccessingSecurityScopedResource()
            Self.authorizedFolderAccessActive = false
        }
        Self.authorizedFolderURL = nil
        authorizedFolderDisplayName = nil
        UserDefaults.standard.removeObject(forKey: Self.authorizedFolderBookmarkKey)
    }
    
    private func restoreAuthorizedFolderAccess() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.authorizedFolderBookmarkKey) else {
            return
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &isStale)
            if isStale {
                setAuthorizedFolder(url)
            } else {
                Self.authorizedFolderURL = url
                if !Self.authorizedFolderAccessActive {
                    Self.authorizedFolderAccessActive = url.startAccessingSecurityScopedResource()
                }
                authorizedFolderDisplayName = url.lastPathComponent
            }
        } catch {
            errorMessage = "Folder access expired: \(error.localizedDescription)"
            stopAuthorizedFolderAccess()
        }
    }
}
