//
//  RepertoireAnalysisController.swift
//  MacStudioServerSimulator
//
//  Controller for Repertoire tab analysis with proper concurrency.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class RepertoireAnalysisController: ObservableObject {
    @Published var rows: [RepertoireRow] = []
    @Published var spotifyTracks: [RepertoireSpotifyTrack] = []
    @Published var isAnalyzing = false
    @Published var alertMessage: String?
    
    private let manager: MacStudioServerManager
    // Hard cap per preview clip; raised to 180s to allow slow songs to finish under load.
    private let rowTimeoutSeconds: TimeInterval = 180
    private var analysisTask: Task<Void, Never>?
    private let defaultNamespace = "repertoire-90"
    // Preview rows intentionally withheld from automated tests.
    private let excludedRowNumbers: Set<Int> = [64, 73]
    
    init(manager: MacStudioServerManager) {
        self.manager = manager
    }
    
    // MARK: - Analysis
    func startAnalysisFromButton() {
        // Kick off a structured task owned by the controller so SwiftUI lifecycle doesn't cancel it.
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runFullAnalysisSession()
        }
    }
    
    private func runFullAnalysisSession() async {
        print("[ENTRY] runFullAnalysisSession() called")
        print("[STATE] rows.count=\(rows.count), isAnalyzing=\(isAnalyzing)")
        
        guard !isAnalyzing else {
            print("⚠️ Already analyzing; ignoring new request")
            return
        }
        guard !rows.isEmpty else {
            print("⚠️ Cannot start analysis: rows are empty")
            alertMessage = "Load preview files before analyzing."
            return
        }
        
        isAnalyzing = true
        alertMessage = nil
        defer {
            isAnalyzing = false
            analysisTask = nil
        }
        
        print("🚀 Starting analysis for \(rows.count) rows")
        print("[SERVER] Launching dedicated analyzer for Repertoire run…")
        
        // Repertoire runs manage their own analyzer lifecycle, similar to run_test.sh:
        // always spin up a fresh server instance, then tear it down when done.
        await manager.startServer()
        print("[SERVER] startServer() returned (isServerRunning=\(manager.isServerRunning))")
        
        guard manager.isServerRunning else {
            print("❌ Server is not running after startServer()")
            alertMessage = AudioAnalysisError.serverOffline.errorDescription ?? "Server offline"
            return
        }
        
        print("✓ Server is running, proceeding with analysis")
        print("[STEP 1] Calling runAnalysisBatches...")
        await runAnalysisBatches()
        print("[STEP 2] runAnalysisBatches returned")
        print("🏁 Analysis complete")
        
        print("[SERVER] Stopping analyzer after Repertoire run…")
        await manager.stopServer(userTriggered: false)
        print("[SERVER] stopServer() returned (isServerRunning=\(manager.isServerRunning))")
        print("[EXIT] runFullAnalysisSession() complete")
    }
    
    private func runAnalysisBatches() async {
        print("[BATCH ENTRY] runAnalysisBatches() called")
        
        let indices = Array(rows.indices)
        let maxConcurrent = 6
        print("[POOL] Bounded concurrent analysis for \(indices.count) rows (max \(maxConcurrent))")
        
        var start = 0
        while start < indices.count {
            let end = min(start + maxConcurrent, indices.count)
            let batch = Array(indices[start..<end])
            print("[POOL] Starting batch \(start + 1)-\(end) (size \(batch.count))")
            
            // Refresh the analyzer between batches to recover from any worker crashes.
            if start > 0 {
                print("[POOL] Restarting analyzer before batch \(start + 1)-\(end)")
                await manager.restartServer()
                guard manager.isServerRunning else {
                    print("❌ Analyzer not running after restart; aborting remaining batches")
                    return
                }
            } else if !manager.isServerRunning {
                print("[POOL] Analyzer not running at batch start; starting now")
                await manager.startServer()
                guard manager.isServerRunning else {
                    print("❌ Analyzer failed to start; aborting run")
                    return
                }
            }
            
            await withTaskGroup(of: Void.self) { group in
                for idx in batch {
                    print("[POOL] Starting task for row index \(idx)")
                    group.addTask { [weak self] in
                        await self?.analyzeRowNonisolated(at: idx)
                    }
                }
                await group.waitForAll()
            }
            
            print("[POOL] Finished batch \(start + 1)-\(end)")
            start = end
        }
        
        print("[POOL EXIT] All rows processed")
    }
    
    private func analyzeRow(at index: Int) async {
        print("[ROW \(index)] analyzeRow() called")
        
        guard rows.indices.contains(index) else { 
            print("[ROW \(index)] ERROR: Index out of bounds")
            return 
        }
        
        print("[ROW \(index)] Setting status to .running")
        rows[index].status = .running
        let fileURL = rows[index].url
        print("[ROW \(index)] File: \(rows[index].fileName)")
        print("[ROW \(index)] URL: \(fileURL.path)")
        
        do {
            let clientId = "repertoire-row-\(index + 1)"
            print("[ROW \(index)] Calling manager.analyzeAudioFile… (clientId=\(clientId))")
            let result = try await manager.analyzeAudioFile(
                at: fileURL,
                skipChunkAnalysis: false,
                forceFreshAnalysis: true,
                cacheNamespace: defaultNamespace,
                clientRequestId: clientId
            )
            print("[ROW \(index)] manager.analyzeAudioFile returned successfully")
            
            guard rows.indices.contains(index) else { 
                print("[ROW \(index)] WARNING: Index out of bounds after analysis")
                return 
            }
            
            print("[ROW \(index)] Updating row with results")
            rows[index].analysis = result
            rows[index].status = .done
            rows[index].bpmMatch = bpmMatch(for: rows[index])
            rows[index].keyMatch = keyMatch(for: rows[index])
            
            print("✓ Row \(index + 1): \(rows[index].fileName) - BPM: \(result.bpm), Key: \(result.key)")
        } catch {
            print("[ROW \(index)] ERROR caught: \(error.localizedDescription)")
            guard rows.indices.contains(index) else { 
                print("[ROW \(index)] WARNING: Index out of bounds in catch block")
                return 
            }
            rows[index].status = .failed
            rows[index].error = error.localizedDescription
            
            print("✗ Row \(index + 1): \(rows[index].fileName) - Error: \(error.localizedDescription)")
        }
        
        print("[ROW \(index)] analyzeRow() exiting")
    }
    
    // Version that can run off the main actor for true concurrency
    private nonisolated func analyzeRowNonisolated(at index: Int) async {
        print("[ROW \(index)] analyzeRowNonisolated() called (nonisolated)")
        
        // Capture row data from main actor
        let rowData: (url: URL, title: String, artist: String, fileName: String)? = await MainActor.run {
            guard rows.indices.contains(index) else {
                print("[ROW \(index)] ERROR: Index out of bounds")
                return nil
            }
            print("[ROW \(index)] Setting status to .running")
            rows[index].status = .running
            let row = rows[index]
            print("[ROW \(index)] File: \(row.fileName)")
            print("[ROW \(index)] URL: \(row.url.path)")
            return (url: row.url, title: row.displayTitle, artist: row.displayArtist, fileName: row.fileName)
        }
        
        guard let rowData else { return }
        
        guard !rowData.url.path.isEmpty else { return }
        
        // Get namespace value
        let namespace: String = await MainActor.run { defaultNamespace }
        let timeout: TimeInterval = await MainActor.run { rowTimeoutSeconds }
        let clientId = "repertoire-row-\(index + 1)"
        
        // Perform network I/O off main actor with a bounded per-request timeout.
        // If the analyzer drops or times out, restart once and retry the row.
        var attempt = 0
        while attempt < 2 {
            attempt += 1
            do {
                // Ensure analyzer is up before firing the request (covers mid-run crashes).
                let serverRunning = await MainActor.run { manager.isServerRunning }
                if !serverRunning {
                    print("[ROW \(index)] Analyzer not running; restarting before attempt \(attempt)")
                    await manager.startServer()
                }
                
                print("[ROW \(index)] Calling manager.analyzeAudioFile… (off main actor, timeout=\(timeout)s, titleOverride=\(rowData.title), artistOverride=\(rowData.artist), clientId=\(clientId), attempt=\(attempt))")
                let result = try await self.manager.analyzeAudioFile(
                    at: rowData.url,
                    skipChunkAnalysis: false,
                    forceFreshAnalysis: true,
                    cacheNamespace: namespace,
                    requestTimeout: timeout,
                    titleOverride: rowData.title,
                    artistOverride: rowData.artist,
                    clientRequestId: clientId
                )
                print("[ROW \(index)] manager.analyzeAudioFile returned successfully")
                
                // Update UI on main actor
                await MainActor.run {
                    guard rows.indices.contains(index) else {
                        print("[ROW \(index)] WARNING: Index out of bounds after analysis")
                        return
                    }
                    
                    print("[ROW \(index)] Updating row with results")
                    rows[index].analysis = result
                    rows[index].status = .done
                    rows[index].bpmMatch = bpmMatch(for: rows[index])
                    rows[index].keyMatch = keyMatch(for: rows[index])
                    
                    print("✓ Row \(index + 1): \(rows[index].fileName) - BPM: \(result.bpm), Key: \(result.key)")
                }
                return
            } catch {
                let nsError = error as NSError
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    print("[ROW \(index)] ERROR: Network timed out (\(timeout)s) on attempt \(attempt)")
                } else if nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue {
                    print("[ROW \(index)] ERROR: Network timed out (\(timeout)s) [NSError] on attempt \(attempt)")
                } else {
                    print("[ROW \(index)] ERROR caught on attempt \(attempt): \(error.localizedDescription)")
                }
                
                // If first attempt failed, restart analyzer and retry once.
                if attempt < 2 {
                    print("[ROW \(index)] Restarting analyzer after failure; will retry")
                    await manager.restartServer()
                    continue
                }
                
                await MainActor.run {
                    guard rows.indices.contains(index) else {
                        print("[ROW \(index)] WARNING: Index out of bounds in catch block")
                        return
                    }
                    rows[index].status = .failed
                    rows[index].error = error.localizedDescription
                    let message = rows[index].error ?? "Unknown error"
                    print("✗ Row \(index + 1): \(rows[index].fileName) - Error: \(message)")
                }
            }
        }
        
        print("[ROW \(index)] analyzeRowNonisolated() exiting")
    }
    
    // MARK: - Data Loading
    
    func loadDefaultSpotify() async {
        let csvURL = manager.repoRootURL
            .appendingPathComponent("csv")
            .appendingPathComponent("90 preview list.csv")
        print("📊 Loading Spotify CSV from: \(csvURL.path)")
        await loadSpotify(from: csvURL)
    }
    
    func loadDefaultFolder() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home
            .appendingPathComponent("Documents")
            .appendingPathComponent("Git repo")
            .appendingPathComponent("Songwise 1")
            .appendingPathComponent("preview_samples_repertoire_90")
        print("📁 Loading default folder from: \(folder.path)")
        await importFolder(folder)
    }
    
    func reloadSpotify() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            await loadSpotify(from: url)
        }
    }
    
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await importFolder(url) }
        }
    }
    
    func handleDrop(_ urls: [URL]) -> Bool {
        let audio = urls.filter { RepertoireFileParser.isAudio($0) }
        guard !audio.isEmpty else {
            alertMessage = "Unsupported file type. Drop .m4a or .mp3 files or a folder."
            return false
        }
        Task { await importFiles(audio) }
        return true
    }
    
    func importFolder(_ folder: URL) async {
        guard FileManager.default.fileExists(atPath: folder.path) else { 
            print("⚠️ Folder does not exist: \(folder.path)")
            return 
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let audio = contents.filter { RepertoireFileParser.isAudio($0) }
            print("🎵 Found \(audio.count) audio files in folder")
            await importFiles(audio.sorted { $0.lastPathComponent < $1.lastPathComponent })
        } catch {
            print("❌ Error importing folder: \(error.localizedDescription)")
            alertMessage = error.localizedDescription
        }
    }
    
    func importFiles(_ files: [URL]) async {
        guard !files.isEmpty else { 
            print("⚠️ No files to import")
            return 
        }
        var skippedNames: [String] = []
        let allowedFiles = files.filter { url in
            guard let rowIndex = rowNumber(fromFileName: url.lastPathComponent) else {
                return true
            }
            if excludedRowNumbers.contains(rowIndex) {
                skippedNames.append(url.lastPathComponent)
                return false
            }
            return true
        }
        if !skippedNames.isEmpty {
            print("⚠️ Skipping \(skippedNames.count) excluded file(s): \(skippedNames.joined(separator: ", "))")
        }
        guard !allowedFiles.isEmpty else {
            print("⚠️ All provided files are excluded from repertoire tests")
            rows = []
            return
        }
        var newRows: [RepertoireRow] = []
        for (idx, url) in allowedFiles.enumerated() {
            let parsed = RepertoireFileParser.parse(fileName: url.lastPathComponent)
            let row = RepertoireRow(
                index: idx + 1,
                url: url,
                fileName: url.lastPathComponent,
                artistGuess: parsed.artist,
                titleGuess: parsed.title
            )
            newRows.append(row)
        }
        rows = newRows
        print("✅ Imported \(rows.count) rows")
        applyIndexMappingIf1to1()
    }
    
    func loadSpotify(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is not UTF-8"])
            }
            let parsed = try RepertoireSpotifyParser.parse(text: text)
            spotifyTracks = parsed.filter { track in
                guard let index = track.csvIndex else { return true }
                return !excludedRowNumbers.contains(index)
            }
            print("✅ Loaded \(spotifyTracks.count) Spotify tracks")
            applyIndexMappingIf1to1()
        } catch {
            print("❌ Failed to load Spotify CSV: \(error.localizedDescription)")
            alertMessage = "Failed to load Spotify CSV: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    
    var currentFolderPath: String? {
        rows.first?.url.deletingLastPathComponent().path
    }
    
    var summaryLine: String {
        let withSpotify = rows.filter { $0.spotify != nil }.count
        let bpmMatches = rows.filter { $0.bpmMatch.isMatch }.count
        let keyMatches = rows.filter { $0.keyMatch.isMatch }.count
        return "Matched \(withSpotify)/\(rows.count) to Spotify • BPM \(bpmMatches)/\(rows.count) • Key \(keyMatches)/\(rows.count)"
    }

    // Tab-separated values for Detected BPM / Key, suitable for pasting into spreadsheets.
    private var detectedBpmKeyTSV: String {
        guard !rows.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("Detected BPM\tDetected Key")
        for row in rows {
            let bpmText: String
            if let bpm = row.analysis?.bpm {
                bpmText = String(format: "%.1f", bpm)
            } else {
                bpmText = ""
            }
            let keyText = row.analysis?.key ?? ""
            lines.append("\(bpmText)\t\(keyText)")
        }
        return lines.joined(separator: "\n")
    }

    func copyDetectedBpmKeyToClipboard() {
        let tsv = detectedBpmKeyTSV
        guard !tsv.isEmpty else { return }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tsv, forType: .string)
        #endif
    }
    
    private func matchSpotify(for row: RepertoireRow) -> RepertoireSpotifyTrack? {
        guard !spotifyTracks.isEmpty else { return nil }
        let normTitle = RepertoireMatchNormalizer.normalize(row.titleGuess)
        let normArtist = RepertoireMatchNormalizer.normalize(row.artistGuess)
        
        if let exact = spotifyTracks.first(where: {
            RepertoireMatchNormalizer.normalize($0.song) == normTitle &&
            RepertoireMatchNormalizer.normalize($0.artist) == normArtist
        }) {
            return exact
        }
        
        if let byTitle = spotifyTracks.first(where: {
            RepertoireMatchNormalizer.normalize($0.song) == normTitle
        }) {
            return byTitle
        }
        
        return nil
    }
    
    private func bpmMatch(for row: RepertoireRow) -> MetricMatch {
        guard let spotify = row.spotify?.bpm, let analysis = row.analysis?.bpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(analysis)),
            spotify: Int(round(spotify))
        )
    }
    
    private func keyMatch(for row: RepertoireRow) -> MetricMatch {
        guard let spotify = row.spotify?.key, let analysis = row.analysis?.key else {
            return .unavailable
        }
        return ComparisonEngine.compareKey(
            analyzed: analysis,
            spotify: spotify
        )
    }
    
    private func applyIndexMappingIf1to1() {
        guard !rows.isEmpty,
              spotifyTracks.count == rows.count else {
            // Fallback: heuristic matching for partial or mismatched lists
            rows = rows.map { row in
                var updated = row
                if updated.spotify == nil {
                    updated.spotify = matchSpotify(for: row)
                }
                return updated
            }
            return
        }
        for index in rows.indices {
            rows[index].spotify = spotifyTracks[index]
        }
    }

    private func rowNumber(fromFileName fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let prefix = stem.split(separator: "_").first else { return nil }
        return Int(prefix)
    }
}
