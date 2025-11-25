//
//  RepertoireAnalysisController+DataLoading.swift
//  MacStudioServerSimulator
//
//  Loading reference CSVs and ingesting preview files.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

extension RepertoireAnalysisController {
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
}
