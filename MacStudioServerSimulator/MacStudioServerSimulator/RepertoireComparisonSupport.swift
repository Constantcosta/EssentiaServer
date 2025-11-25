//
//  RepertoireComparisonSupport.swift
//  MacStudioServerSimulator
//
//  Support types for repertoire comparison (audio playback, models, parsers).
//

import SwiftUI
import AVFoundation
import AppKit

// MARK: - Audio

@MainActor
final class RepertoireAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var currentlyPlayingRowID: UUID?
    
    private var player: AVAudioPlayer?
    
    func togglePlayback(for row: RepertoireRow) {
        if currentlyPlayingRowID == row.id {
            stopPlayback()
        } else {
            startPlayback(url: row.url, rowID: row.id)
        }
    }
    
    func isPlaying(_ row: RepertoireRow) -> Bool {
        currentlyPlayingRowID == row.id && (player?.isPlaying ?? false)
    }
    
    private func startPlayback(url: URL, rowID: UUID) {
        stopPlayback()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            player = newPlayer
            currentlyPlayingRowID = rowID
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
        } catch {
            NSSound.beep()
            currentlyPlayingRowID = nil
            player = nil
        }
    }
    
    private func stopPlayback() {
        player?.stop()
        player = nil
        currentlyPlayingRowID = nil
    }
}

// Delegate callbacks can fire off the main thread; hop onto the main actor before mutating state.
extension RepertoireAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
}

// MARK: - Models

struct RepertoireRow: Identifiable {
    let id = UUID()
    let index: Int
    let url: URL
    let fileName: String
    let artistGuess: String
    let titleGuess: String
    
    // Prefer Spotify metadata when available; file-name parsing is a fallback.
    var displayArtist: String { spotify?.artist ?? artistGuess }
    var displayTitle: String { spotify?.song ?? titleGuess }
    
    var spotify: RepertoireSpotifyTrack?
    var analysis: MacStudioServerManager.AnalysisResult?
    var bpmMatch: MetricMatch = .unavailable
    var keyMatch: MetricMatch = .unavailable
    var bpmTruthExcluded: Bool = false
    var status: RepertoireStatus = .pending
    var error: String?
    
    var detectedBpmText: String {
        guard let bpm = analysis?.bpm else { return "—" }
        return String(format: "%.1f", bpm)
    }
    
    var detectedKeyText: String {
        analysis?.key ?? "—"
    }
    
    var hasBpmTruth: Bool {
        truthBpmValue != nil && !bpmTruthExcluded
    }
    
    var hasAnyTruth: Bool {
        hasTruthKey || hasBpmTruth
    }
    
    var songBpmText: String {
        guard let bpm = spotify?.songBpm else { return "—" }
        return String(format: "%.0f", bpm)
    }
    
    var deezerBpmValue: Double? {
        spotify?.deezerApiBpm ?? spotify?.deezerBpm
    }
    
    var deezerBpmText: String {
        guard let bpm = deezerBpmValue else { return "—" }
        return String(format: "%.0f", bpm)
    }
    
    private var truthBpmCandidates: [Double] {
        if let truth = spotify?.truthBpm {
            return [truth]
        }
        return [
            spotify?.googleBpm,
            spotify?.deezerApiBpm,
            spotify?.deezerBpm,
            spotify?.songBpm,
            spotify?.bpm
        ].compactMap { $0 }
    }
    
    var truthBpmValue: Double? {
        guard !truthBpmCandidates.isEmpty else { return nil }
        let sorted = truthBpmCandidates.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
    
    var truthBpmText: String {
        guard let bpm = truthBpmValue else { return "—" }
        return String(format: "%.0f", bpm)
    }
    
    var truthKeyText: String {
        spotify?.truthKeyLabel ?? "—"
    }
    
    var hasTruthKey: Bool {
        spotify?.truthKeyLabel != nil
    }
    
    var truthConfidenceLabel: String? {
        guard !truthBpmCandidates.isEmpty else { return nil }
        if spotify?.truthBpm != nil {
            return "Manual truth"
        }
        let spread = (truthBpmCandidates.max() ?? 0) - (truthBpmCandidates.min() ?? 0)
        if truthBpmCandidates.count <= 1 {
            return "Low confidence"
        } else if spread <= 3 {
            return "High confidence"
        } else if spread <= 6 {
            return "Medium confidence"
        } else {
            return "Low confidence"
        }
    }
    
    var truthConfidenceColor: Color {
        guard let label = truthConfidenceLabel else { return .secondary }
        switch label {
        case "Manual truth": return .green
        case "High confidence": return .green
        case "Medium confidence": return .orange
        case "Low confidence": return .red
        default: return .secondary
        }
    }
    
    var spotifyKeyVsTruth: MetricMatch {
        guard let truth = spotify?.truthKeyLabel else {
            return .unavailable
        }
        return ComparisonEngine.compareKey(
            analyzed: spotify?.key,
            reference: truth
        )
    }
    
    var spotifyBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let spotifyBpm = spotify?.bpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(spotifyBpm)),
            spotify: Int(round(truth))
        )
    }
    
    var googleKeyVsTruth: MetricMatch {
        guard let truth = spotify?.truthKeyLabel,
              let googleKey = spotify?.googleKey else {
            return .unavailable
        }
        return ComparisonEngine.compareKey(
            analyzed: googleKey,
            reference: truth
        )
    }
    
    var googleBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let googleBpm = spotify?.googleBpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(googleBpm)),
            spotify: Int(round(truth))
        )
    }
    
    var songBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let songBpm = spotify?.songBpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(songBpm)),
            spotify: Int(round(truth))
        )
    }
    
    var deezerBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let deezer = deezerBpmValue else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(deezer)),
            spotify: Int(round(truth))
        )
    }
    
    private func wins(key: MetricMatch, bpm: MetricMatch) -> Bool {
        let keyOk = hasTruthKey ? key.isMatch : true
        let bpmOk = hasBpmTruth ? bpm.isMatch : true
        return keyOk && bpmOk
    }
    
    var spotifyWins: Bool {
        wins(key: spotifyKeyVsTruth, bpm: spotifyBpmVsTruth)
    }
    
    var googleWins: Bool {
        wins(key: googleKeyVsTruth, bpm: googleBpmVsTruth)
    }
    
    var songwiseWins: Bool {
        wins(key: keyMatch, bpm: bpmMatch)
    }
    
    private func winnerLabel(for matches: [(String, Bool)]) -> String {
        let winners = matches.filter { $0.1 }.map { $0.0 }
        guard !winners.isEmpty else { return "—" }
        return winners.count == 1 ? winners[0] : "Tie"
    }
    
    var bpmWinnerLabel: String {
        guard hasBpmTruth else { return "—" }
        return winnerLabel(
            for: [
                ("Spotify", spotifyBpmVsTruth.isMatch),
                ("Google", googleBpmVsTruth.isMatch),
                ("Songwise", bpmMatch.isMatch)
            ]
        )
    }
    
    var keyWinnerLabel: String {
        guard hasTruthKey else { return "—" }
        return winnerLabel(
            for: [
                ("Spotify", spotifyKeyVsTruth.isMatch),
                ("Google", googleKeyVsTruth.isMatch),
                ("Songwise", keyMatch.isMatch)
            ]
        )
    }
    
    var bpmWinnerColor: Color {
        bpmWinnerLabel == "—" ? .secondary : .green
    }
    
    var keyWinnerColor: Color {
        keyWinnerLabel == "—" ? .secondary : .green
    }
    
    var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .running: return "Running"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .done: return .green
        case .failed: return .red
        }
    }
}

enum RepertoireStatus {
    case pending
    case running
    case done
    case failed
}

struct RepertoireSpotifyTrack: Identifiable {
    let id = UUID()
    let csvIndex: Int?
    let song: String
    let artist: String
    let bpm: Double
    let key: String
    var googleBpm: Double?
    var songBpm: Double?
    var deezerBpm: Double?
    var deezerApiBpm: Double?
    let googleKey: String?
    var truthKey: String?
    let keyQuality: String?
    var truthBpm: Double?
    var truthNotes: String?
    
    var bpmText: String {
        String(format: "%.0f", bpm)
    }
    
    var googleBpmText: String? {
        guard let googleBpm else { return nil }
        return String(format: "%.0f", googleBpm)
    }
    
    var truthKeyLabel: String? {
        let trimmed = truthKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Parsing helpers

enum RepertoireFileParser {
    static func isAudio(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "m4a" || ext == "mp3"
    }
    
    static func parse(fileName: String) -> (artist: String, title: String) {
        var stem = fileName
        if stem.lowercased().hasSuffix(".m4a") {
            stem.removeLast(4)
        } else if stem.lowercased().hasSuffix(".mp3") {
            stem.removeLast(4)
        }
        var parts = stem.split(separator: "_").map { String($0) }
        if let first = parts.first, Int(first) != nil {
            parts.removeFirst()
        }
        guard !parts.isEmpty else {
            return ("Unknown", stem)
        }
        let artist = parts.first ?? "Unknown"
        let title = parts.dropFirst().joined(separator: " ")
        return (artist, title)
    }
}

enum RepertoireMatchNormalizer {
    static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        return cleaned
    }
}

enum RepertoireSpotifyParser {
    static func parse(text: String) throws -> [RepertoireSpotifyTrack] {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        let header = parseRow(lines.removeFirst())
        guard let indexIdx = header.firstIndex(of: "#"),
              let songIdx = header.firstIndex(of: "Song"),
              let artistIdx = header.firstIndex(of: "Artist"),
              let bpmIdx = header.firstIndex(of: "BPM"),
              let keyIdx = header.firstIndex(of: "Key") else {
            throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns (Song, Artist, BPM, Key)"])
        }
        let googleBpmIdx = header.firstIndex(of: "Google BPM")
        let googleKeyIdx = header.firstIndex(of: "Google Key")
        let truthKeyIdx = header.firstIndex(of: "Truth Key")
        let keyQualityIdx = header.firstIndex(of: "Key Quality")
        var result: [RepertoireSpotifyTrack] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(indexIdx, songIdx, artistIdx, bpmIdx, keyIdx) else { continue }
            let csvIndex = Int(cols[indexIdx])
            let song = cols[songIdx]
            let artist = cols[artistIdx]
            let bpm = Double(cols[bpmIdx]) ?? 0
            let key = cols[keyIdx]
            let googleBpm: Double?
            if let idx = googleBpmIdx, idx < cols.count {
                googleBpm = Double(cols[idx])
            } else {
                googleBpm = nil
            }
            let googleKey: String?
            if let idx = googleKeyIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                googleKey = value.isEmpty ? nil : value
            } else {
                googleKey = nil
            }
            let truthKey: String?
            if let idx = truthKeyIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                truthKey = value.isEmpty ? nil : value
            } else {
                truthKey = nil
            }
            let keyQuality: String?
            if let idx = keyQualityIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                keyQuality = value.isEmpty ? nil : value
            } else {
                keyQuality = nil
            }
            result.append(
                RepertoireSpotifyTrack(
                    csvIndex: csvIndex,
                    song: song,
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    googleBpm: googleBpm,
                    songBpm: nil,
                    deezerBpm: nil,
                    deezerApiBpm: nil,
                    googleKey: googleKey,
                    truthKey: truthKey,
                    keyQuality: keyQuality,
                    truthBpm: nil,
                    truthNotes: nil
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
