//
//  RepertoireAnalysisController+Helpers.swift
//  MacStudioServerSimulator
//
//  Helper utilities and exports for repertoire analysis.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension RepertoireAnalysisController {
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
    
    func exportCalibrationLog() {
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
    
    func matchSpotify(for row: RepertoireRow) -> RepertoireSpotifyTrack? {
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
    
    func bpmMatch(for row: RepertoireRow) -> MetricMatch {
        guard let reference = row.truthBpmValue, let analysis = row.analysis?.bpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(analysis)),
            spotify: Int(round(reference))
        )
    }
    
    func keyMatch(for row: RepertoireRow) -> MetricMatch {
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
    
    func applyIndexMappingIf1to1() {
        guard !rows.isEmpty,
              spotifyTracks.count == rows.count else {
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
    
    func applyBpmGoogleMapping(from references: [BpmReferenceRow]) {
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
    
    func overlayTruthOntoSpotify() {
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
    
    func rowNumber(fromFileName fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let prefix = stem.split(separator: "_").first else { return nil }
        return Int(prefix)
    }
    
    func shouldExcludeFromBpmTruth(row: RepertoireRow) -> Bool {
        let title = row.spotify?.song ?? row.titleGuess
        return excludedBpmTruthTitles.contains(title)
    }
}
