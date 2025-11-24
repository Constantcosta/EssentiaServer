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
import UniformTypeIdentifiers

struct BpmReferenceRow {
    let songTitle: String
    let artist: String
    let googleBpm: Double
    let songBpm: Double?
    let deezerBpm: Double?
    let deezerApiBpm: Double?
}

enum BpmReferenceParser {
    static func parse(text: String) throws -> [BpmReferenceRow] {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        let header = parseRow(lines.removeFirst())
        guard let titleIdx = header.firstIndex(of: "Song Title"),
              let artistIdx = header.firstIndex(of: "Artist"),
              let googleIdx = header.firstIndex(of: "Google BPM") else {
            throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns (Song Title, Artist, Google BPM)"])
        }
        let songBpmIdx = header.firstIndex(of: "SongBPM BPM")
        let deezerBpmIdx = header.firstIndex(of: "Deezer BPM")
        let deezerApiBpmIdx = header.firstIndex(of: "Deezer API BPM")
        
        var result: [BpmReferenceRow] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(titleIdx, artistIdx, googleIdx) else { continue }
            let title = cols[titleIdx]
            let artist = cols[artistIdx]
            guard let google = Double(cols[googleIdx]) else { continue }
            let songBpm: Double?
            if let idx = songBpmIdx, idx < cols.count {
                songBpm = Double(cols[idx])
            } else {
                songBpm = nil
            }
            let deezerBpm: Double?
            if let idx = deezerBpmIdx, idx < cols.count {
                deezerBpm = Double(cols[idx])
            } else {
                deezerBpm = nil
            }
            let deezerApiBpm: Double?
            if let idx = deezerApiBpmIdx, idx < cols.count {
                deezerApiBpm = Double(cols[idx])
            } else {
                deezerApiBpm = nil
            }
            result.append(
                BpmReferenceRow(
                    songTitle: title,
                    artist: artist,
                    googleBpm: google,
                    songBpm: songBpm,
                    deezerBpm: deezerBpm,
                    deezerApiBpm: deezerApiBpm
                )
            )
        }
        return result
    }
    
    private static func parseRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)
        return columns
    }
}

struct TruthReferenceRow {
    let song: String
    let artist: String
    let bpm: Double
    let key: String
    let notes: String?
}

enum TruthReferenceParser {
    static func parse(text: String) throws -> [TruthReferenceRow] {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        let header = parseRow(lines.removeFirst())
        guard let songIdx = header.firstIndex(of: "Song"),
              let artistIdx = header.firstIndex(of: "Artist"),
              let bpmIdx = header.firstIndex(of: "BPM"),
              let keyIdx = header.firstIndex(of: "Key") else {
            throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns (Song, Artist, BPM, Key)"])
        }
        let notesIdx = header.firstIndex(of: "Notes") ?? header.firstIndex(of: "Comment")
        
        var result: [TruthReferenceRow] = []
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(songIdx, artistIdx, bpmIdx, keyIdx) else { continue }
            guard let bpm = Double(cols[bpmIdx]) else { continue }
            let song = cols[songIdx]
            let artist = cols[artistIdx]
            let key = cols[keyIdx]
            let notes: String?
            if let idx = notesIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                notes = value.isEmpty ? nil : value
            } else {
                notes = nil
            }
            result.append(
                TruthReferenceRow(
                    song: song,
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    notes: notes
                )
            )
        }
        return result
    }
    
    private static func parseRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)
        return columns
    }
}

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
    // Separate cache namespace for the curated repertoire subset.
    private let defaultNamespace = "repertoire-subset"
    // Preview rows intentionally withheld from automated tests.
    private let excludedRowNumbers: Set<Int> = [64, 73]
    // Optional list of song titles that should be excluded from BPM truth win/loss stats.
    // These correspond to ambiguous rows in the 80 BPM comparison sheet.
    private let excludedBpmTruthTitles: Set<String> = []
    private var bpmReferenceRows: [BpmReferenceRow] = []
    private var truthRows: [TruthReferenceRow] = []
    
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
        
        print("[LOG] Exporting calibration summary log…")
        exportCalibrationLog()
        
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
            
            // Ensure the analyzer is up, but avoid per-batch restarts that can freeze the UI.
            if !manager.isServerRunning {
                let label = "\(start + 1)-\(end)"
                print("[POOL] Analyzer offline before batch \(label); starting now")
                await manager.startServer(skipPreflight: start > 0)
                guard manager.isServerRunning else {
                    print("❌ Analyzer failed to start before batch \(label); aborting run")
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
            .appendingPathComponent("repertoire_subset_google.csv")
        print("📊 Loading Spotify CSV from: \(csvURL.path)")
        await loadSpotify(from: csvURL)
    }
    
    func loadDefaultTruth() async {
        let csvURL = manager.repoRootURL
            .appendingPathComponent("csv")
            .appendingPathComponent("truth_repertoire_manual.csv")
        print("📊 Loading manual truth CSV from: \(csvURL.path)")
        await loadTruth(from: csvURL)
    }
    
    func loadDefaultBpmReferences() async {
        let csvURL = manager.repoRootURL
            .appendingPathComponent("csv")
            .appendingPathComponent("80_bpm_complete.csv")
        print("📊 Loading 80 BPM reference CSV from: \(csvURL.path)")
        await loadBpmReferences(from: csvURL)
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
    
    func reloadTruth() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            await loadTruth(from: url)
        }
    }
    
    private func loadBpmReferences(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is not UTF-8"])
            }
            let parsed = try BpmReferenceParser.parse(text: text)
            print("✅ Loaded \(parsed.count) BPM reference rows")
            applyBpmGoogleMapping(from: parsed)
        } catch {
            print("❌ Failed to load BPM reference CSV: \(error.localizedDescription)")
        }
    }
    
    private func loadTruth(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is not UTF-8"])
            }
            let parsed = try TruthReferenceParser.parse(text: text)
            truthRows = parsed
            print("✅ Loaded \(parsed.count) manual truth rows")
            overlayTruthOntoSpotify()
        } catch {
            print("❌ Failed to load manual truth CSV: \(error.localizedDescription)")
            alertMessage = "Failed to load truth CSV: \(error.localizedDescription)"
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
        let allowedCsvIndexes = Set(spotifyTracks.compactMap { $0.csvIndex })
        let allowedFiles = files.filter { url in
            guard let rowIndex = rowNumber(fromFileName: url.lastPathComponent) else {
                // If we can't infer an index, keep the file unless we're strictly
                // filtering by the curated subset (in which case ad‑hoc files are okay).
                return true
            }
            if excludedRowNumbers.contains(rowIndex) {
                skippedNames.append(url.lastPathComponent)
                return false
            }
            if !allowedCsvIndexes.isEmpty && !allowedCsvIndexes.contains(rowIndex) {
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
            overlayTruthOntoSpotify()
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
        let bpmEligible = rows.filter { $0.truthBpmValue != nil && !$0.bpmTruthExcluded }.count
        let bpmMatches = rows.filter { $0.bpmMatch.isMatch && $0.truthBpmValue != nil && !$0.bpmTruthExcluded }.count
        let keyMatches = rows.filter { $0.keyMatch.isMatch }.count
        return "Matched \(withSpotify)/\(rows.count) to Spotify • BPM \(bpmMatches)/\(bpmEligible) • Key \(keyMatches)/\(rows.count)"
    }
    
    var overallWinnerLabel: String {
        overallWinner.label
    }
    
    var overallWinnerColor: Color {
        overallWinner.color
    }
    
    var overallWinnerDetail: String {
        overallWinner.detail
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
    
    func exportResults(includeOnlyMismatches: Bool = false) {
        guard !rows.isEmpty else {
            alertMessage = "No rows to export."
            return
        }
        
        func isMismatch(_ row: RepertoireRow) -> Bool {
            let bpmBad: Bool
            switch row.bpmMatch {
            case .mismatch: bpmBad = row.hasBpmTruth
            default: bpmBad = false
            }
            let keyBad: Bool
            switch row.keyMatch {
            case .mismatch: keyBad = row.hasTruthKey
            default: keyBad = false
            }
            return bpmBad || keyBad
        }
        
        let filtered = includeOnlyMismatches ? rows.filter(isMismatch) : rows
        guard !filtered.isEmpty else {
            alertMessage = includeOnlyMismatches ? "No mismatches to export." : "No rows to export."
            return
        }
        
        func describe(_ match: MetricMatch) -> String {
            switch match {
            case .match: return "match"
            case .mismatch(let expected, let actual): return "mismatch(expected=\(expected), actual=\(actual))"
            case .unavailable: return "unavailable"
            }
        }
        
        var lines: [String] = []
        lines.append(
            [
                "Index",
                "File",
                "Artist",
                "Title",
                "Truth BPM",
                "Truth Key",
                "Truth Confidence",
                "Spotify BPM",
                "Spotify Key",
                "Google BPM",
                "Google Key",
                "SongBPM",
                "Deezer BPM",
                "Detected BPM",
                "Detected Key",
                "BPM Match",
                "Key Match",
                "BPM Winner",
                "Key Winner",
                "Status",
                "Error"
            ].joined(separator: "\t")
        )
        
        for row in filtered {
            let spotifyBpmText = row.spotify?.bpmText ?? "—"
            let spotifyKey = row.spotify?.key ?? "—"
            let googleBpmText = row.spotify?.googleBpmText ?? "—"
            let googleKey = row.spotify?.googleKey ?? "—"
            let songBpmText = row.spotify?.songBpm != nil ? row.songBpmText : "—"
            let deezerBpmText = row.deezerBpmValue != nil ? row.deezerBpmText : "—"
            let bpmMatchText = describe(row.bpmMatch)
            let keyMatchText = describe(row.keyMatch)
            
            lines.append(
                [
                    "\(row.index)",
                    row.fileName,
                    row.displayArtist,
                    row.displayTitle,
                    row.truthBpmText,
                    row.truthKeyText,
                    row.truthConfidenceLabel ?? "",
                    spotifyBpmText,
                    spotifyKey,
                    googleBpmText,
                    googleKey,
                    songBpmText,
                    deezerBpmText,
                    row.detectedBpmText,
                    row.detectedKeyText,
                    bpmMatchText,
                    keyMatchText,
                    row.bpmWinnerLabel,
                    row.keyWinnerLabel,
                    row.statusText,
                    row.error ?? ""
                ].joined(separator: "\t")
            )
        }
        
        let text = lines.joined(separator: "\n")
        let reportsDir = manager.repoRootURL.appendingPathComponent("reports")
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = includeOnlyMismatches ? "mismatches" : "results"
        let fileURL = reportsDir.appendingPathComponent("repertoire_\(suffix)_\(stamp).tsv")
        
        do {
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            alertMessage = "Exported \(includeOnlyMismatches ? "mismatches" : "results") to \(fileURL.lastPathComponent)"
            print("📄 Exported \(includeOnlyMismatches ? "mismatches" : "results") to \(fileURL.path)")
        } catch {
            alertMessage = "Failed to export \(includeOnlyMismatches ? "mismatches" : "results"): \(error.localizedDescription)"
            print("❌ Failed to export \(includeOnlyMismatches ? "mismatches" : "results"): \(error.localizedDescription)")
        }
    }
    
    func exportMismatches() {
        exportResults(includeOnlyMismatches: true)
    }
    
    private var overallWinner: (label: String, color: Color, detail: String) {
        guard !rows.isEmpty else {
            return ("—", .secondary, "No rows loaded")
        }
        
        var spotifyWins = 0
        var googleWins = 0
        var songwiseWins = 0
        var eligible = 0
        
        for row in rows where row.hasAnyTruth {
            eligible += 1
            if row.spotifyWins { spotifyWins += 1 }
            if row.googleWins { googleWins += 1 }
            if row.songwiseWins { songwiseWins += 1 }
        }
        
        guard eligible > 0 else {
            return ("—", .secondary, "No rows with Truth Key/BPM available")
        }
        
        let maxWins = max(spotifyWins, googleWins, songwiseWins)
        if maxWins == 0 {
            let detail = "Spotify 0, Google 0, Songwise 0 (out of \(eligible) truth-key rows)"
            return ("—", .secondary, detail)
        }
        
        var leaders: [String] = []
        if spotifyWins == maxWins { leaders.append("Spotify") }
        if googleWins == maxWins { leaders.append("Google") }
        if songwiseWins == maxWins { leaders.append("Songwise") }
        
        let detail = "Spotify \(spotifyWins), Google \(googleWins), Songwise \(songwiseWins) (out of \(eligible) truth-key rows)"
        
        if leaders.count == 1, let winner = leaders.first {
            return (winner, .green, detail)
        } else {
            return ("Tie", .orange, detail)
        }
    }
    
    private func exportCalibrationLog() {
        guard !rows.isEmpty else { return }
        
        let total = rows.count
        let keyMatches = rows.filter { $0.keyMatch.isMatch }
        let keyDiffs = rows.filter {
            if case .mismatch = $0.keyMatch { return true }
            return false
        }
        let bpmMatches = rows.filter { $0.bpmMatch.isMatch && $0.truthBpmValue != nil && !$0.bpmTruthExcluded }
        let bpmDiffs = rows.filter {
            if $0.truthBpmValue == nil || $0.bpmTruthExcluded { return false }
            if case .mismatch = $0.bpmMatch { return true }
            return false
        }
        
        func rowLabel(_ row: RepertoireRow) -> String {
            "\(row.index). \(row.displayArtist) – \(row.displayTitle)"
        }
        
        func mismatchDescription(_ match: MetricMatch) -> String? {
            if case .mismatch(let expected, let actual) = match {
                return "expected=\(expected), actual=\(actual)"
            }
            return nil
        }
        
        var lines: [String] = []
        lines.append("Repertoire calibration log")
        lines.append("Summary: \(summaryLine)")
        lines.append("Total rows: \(total)")
        lines.append("")
        
        lines.append("[KEY MATCH \(keyMatches.count)/\(total)]")
        for row in keyMatches {
            let refKey = row.spotify?.truthKeyLabel ?? row.spotify?.key ?? "?"
            let detected = row.analysis?.key ?? "—"
            lines.append("- \(rowLabel(row)) | refKey=\(refKey) | detected=\(detected)")
        }
        lines.append("")
        
        lines.append("[KEY DIFF \(keyDiffs.count)/\(total)]")
        for row in keyDiffs {
            let info = mismatchDescription(row.keyMatch) ?? ""
            lines.append("- \(rowLabel(row)) | \(info)")
        }
        lines.append("")
        
        lines.append("[BPM MATCH \(bpmMatches.count)/\(total)]")
        for row in bpmMatches {
            let refBpm: String
            if let truth = row.truthBpmValue {
                refBpm = String(format: "%.0f", truth)
            } else {
                refBpm = row.spotify.map { String(format: "%.0f", $0.bpm) } ?? "?"
            }
            let detected = row.analysis.map { String(format: "%.1f", $0.bpm) } ?? "—"
            lines.append("- \(rowLabel(row)) | refBpm=\(refBpm) | detected=\(detected)")
        }
        lines.append("")
        
        lines.append("[BPM DIFF \(bpmDiffs.count)/\(total)]")
        for row in bpmDiffs {
            let info = mismatchDescription(row.bpmMatch) ?? ""
            lines.append("- \(rowLabel(row)) | \(info)")
        }
        
        let logText = lines.joined(separator: "\n")
        
        do {
            let root = manager.repoRootURL
            let reportsDir = root.appendingPathComponent("reports", isDirectory: true)
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
            
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let fileURL = reportsDir.appendingPathComponent("repertoire_calibration_\(stamp).log")
            try logText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("📄 Repertoire calibration log written to \(fileURL.path)")
        } catch {
            print("❌ Failed to write calibration log: \(error.localizedDescription)")
        }
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
        guard let reference = row.truthBpmValue, let analysis = row.analysis?.bpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(analysis)),
            spotify: Int(round(reference))
        )
    }
    
    private func keyMatch(for row: RepertoireRow) -> MetricMatch {
        guard let analysis = row.analysis?.key else {
            return .unavailable
        }
        let referenceKey: String
        if let truth = row.spotify?.truthKeyLabel {
            referenceKey = truth
        } else if let spotifyKey = row.spotify?.key {
            referenceKey = spotifyKey
        } else {
            return .unavailable
        }
        return ComparisonEngine.compareKey(
            analyzed: analysis,
            reference: referenceKey
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
                updated.bpmTruthExcluded = shouldExcludeFromBpmTruth(row: updated)
                return updated
            }
            return
        }
        for index in rows.indices {
            rows[index].spotify = spotifyTracks[index]
            rows[index].bpmTruthExcluded = shouldExcludeFromBpmTruth(row: rows[index])
        }
    }

    private func applyBpmGoogleMapping(from references: [BpmReferenceRow]) {
        bpmReferenceRows = references
        guard !spotifyTracks.isEmpty else { return }
        
        func key(forTitle title: String, artist: String) -> String {
            let normTitle = RepertoireMatchNormalizer.normalize(title)
            let normArtist = RepertoireMatchNormalizer.normalize(artist)
            return normTitle + "|" + normArtist
        }
        
        var exactMap: [String: BpmReferenceRow] = [:]
        for ref in references {
            let k = key(forTitle: ref.songTitle, artist: ref.artist)
            exactMap[k] = ref
        }
        
        func matchReference(for track: RepertoireSpotifyTrack) -> BpmReferenceRow? {
            let directKey = key(forTitle: track.song, artist: track.artist)
            if let exact = exactMap[directKey] {
                return exact
            }
            let normSong = RepertoireMatchNormalizer.normalize(track.song)
            if let byTitle = references.first(where: {
                RepertoireMatchNormalizer.normalize($0.songTitle) == normSong
            }) {
                return byTitle
            }
            if let partial = references.first(where: {
                let refNorm = RepertoireMatchNormalizer.normalize($0.songTitle)
                return refNorm.contains(normSong) || normSong.contains(refNorm)
            }) {
                return partial
            }
            return nil
        }
        
        for index in spotifyTracks.indices {
            var track = spotifyTracks[index]
            if let ref = matchReference(for: track) {
                track.googleBpm = ref.googleBpm
                track.songBpm = ref.songBpm
                track.deezerBpm = ref.deezerBpm
                track.deezerApiBpm = ref.deezerApiBpm
                spotifyTracks[index] = track
            }
        }
        applyIndexMappingIf1to1()
    }
    
    private func overlayTruthOntoSpotify() {
        guard !spotifyTracks.isEmpty else { return }
        
        func key(forTitle title: String, artist: String) -> String {
            let normTitle = RepertoireMatchNormalizer.normalize(title)
            let normArtist = RepertoireMatchNormalizer.normalize(artist)
            return normTitle + "|" + normArtist
        }
        
        guard !truthRows.isEmpty else {
            applyIndexMappingIf1to1()
            return
        }
        
        var exactMap: [String: TruthReferenceRow] = [:]
        var byTitle: [String: TruthReferenceRow] = [:]
        
        for truth in truthRows {
            let k = key(forTitle: truth.song, artist: truth.artist)
            exactMap[k] = truth
            let titleKey = RepertoireMatchNormalizer.normalize(truth.song)
            if byTitle[titleKey] == nil {
                byTitle[titleKey] = truth
            }
        }
        
        for index in spotifyTracks.indices {
            var track = spotifyTracks[index]
            let exact = key(forTitle: track.song, artist: track.artist)
            let titleKey = RepertoireMatchNormalizer.normalize(track.song)
            if let truth = exactMap[exact] ?? byTitle[titleKey] {
                track.truthBpm = truth.bpm
                track.truthKey = truth.key
                track.truthNotes = truth.notes
                spotifyTracks[index] = track
            }
        }
        
        applyIndexMappingIf1to1()
    }

    private func rowNumber(fromFileName fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let prefix = stem.split(separator: "_").first else { return nil }
        return Int(prefix)
    }

    private func shouldExcludeFromBpmTruth(row: RepertoireRow) -> Bool {
        guard let title = row.spotify?.song ?? row.titleGuess as String? else {
            return false
        }
        return excludedBpmTruthTitles.contains(title)
    }
}
