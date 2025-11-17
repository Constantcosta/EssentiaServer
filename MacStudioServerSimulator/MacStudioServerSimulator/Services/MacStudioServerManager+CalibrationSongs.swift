import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension MacStudioServerManager {
    // MARK: - Calibration Song Management
    
    func importCalibrationSongs(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        var imported = 0
        for sourceURL in urls {
            if calibrationSongs.count >= calibrationSongLimit {
                calibrationError = "Reached calibration song limit (\(calibrationSongLimit))."
                break
            }
            do {
                let resolved = sourceURL.standardizedFileURL
                let metadata = await inferredMetadata(for: resolved)
                let filename = "\(UUID().uuidString).\(resolved.pathExtension.isEmpty ? "m4a" : resolved.pathExtension)"
                let destination = calibrationSongsDirectory.appendingPathComponent(filename)
                
                let manager = FileManager.default
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                try manager.copyItem(at: resolved, to: destination)
                
                let song = CalibrationSong(
                    id: UUID(),
                    title: metadata.title.isEmpty ? resolved.deletingPathExtension().lastPathComponent : metadata.title,
                    artist: metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist,
                    filename: filename,
                    originalFilename: resolved.lastPathComponent,
                    addedAt: Date()
                )
                
                if calibrationSongs.contains(where: { $0.normalizedMatchKey == song.normalizedMatchKey }) {
                    try? manager.removeItem(at: destination)
                    continue
                }
                
                calibrationSongs.append(song)
                imported += 1
            } catch {
                calibrationError = "Import failed: \(error.localizedDescription)"
                break
            }
        }
        
        if imported > 0 {
            persistCalibrationSongs()
        }
    }
    
    #if os(macOS)
    func promptCalibrationFolderImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Select a folder that contains audio files for calibration."
        if panel.runModal() == .OK, let folder = panel.url {
            let manager = FileManager.default
            let urls = (try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { supportedAudioExtensions.contains($0.pathExtension.lowercased()) }) ?? []
            Task { await importCalibrationSongs(from: urls) }
        }
    }
    #endif
    
    func removeCalibrationSong(_ song: CalibrationSong) {
        let manager = FileManager.default
        let url = fileURL(for: song)
        if manager.fileExists(atPath: url.path) {
            try? manager.removeItem(at: url)
        }
        calibrationSongs.removeAll { $0.id == song.id }
        persistCalibrationSongs()
    }
    
    func removeAllCalibrationSongs() {
        calibrationSongs.removeAll()
        persistCalibrationSongs()
        let manager = FileManager.default
        if let contents = try? manager.contentsOfDirectory(at: calibrationSongsDirectory, includingPropertiesForKeys: nil) {
            for file in contents {
                try? manager.removeItem(at: file)
            }
        }
    }
    
    func resetCalibrationWorkspace(includeExports: Bool) async {
        guard !isResettingCalibration else { return }
        isResettingCalibration = true
        defer { isResettingCalibration = false }
        removeAllCalibrationSongs()
        if includeExports {
            let manager = FileManager.default
            if manager.fileExists(atPath: calibrationExportsDirectory.path) {
                try? manager.removeItem(at: calibrationExportsDirectory)
            }
            ensureDirectoryExists(at: calibrationExportsDirectory)
        }
        calibrationLog = []
        calibrationError = nil
    }
    
    func openCalibrationExportsFolder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([calibrationExportsDirectory])
        #endif
    }
    
    func runCalibration(featureSetVersion: String, notes: String) async {
        await runCalibrationSuite(featureSetVersion: featureSetVersion, notes: notes)
    }
    
    func loadCalibrationSongsFromDisk() {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: calibrationMetadataURL),
              let songs = try? decoder.decode([CalibrationSong].self, from: data) else {
            calibrationSongs = []
            return
        }
        calibrationSongs = songs
    }
    
    private func persistCalibrationSongs() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(calibrationSongs)
            try data.write(to: calibrationMetadataURL, options: .atomic)
        } catch {
            calibrationError = "Failed to save calibration songs: \(error.localizedDescription)"
        }
    }
    
    func fileURL(for song: CalibrationSong) -> URL {
        calibrationSongsDirectory.appendingPathComponent(song.filename)
    }
}
