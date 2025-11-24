//
//  AnalysisComparison.swift
//  MacStudioServerSimulator
//
//  Comparison logic between Essentia analysis and Spotify reference data
//

import Foundation
import SwiftUI

/// Result of analyzing a single track
struct AnalysisResult {
    let song: String
    let artist: String
    let bpm: Int?
    let key: String?
    let success: Bool
    let duration: Double
}

/// Comparison result for a single metric
enum MetricMatch {
    case match
    case mismatch(expected: String, actual: String)
    case unavailable  // Data not available for comparison
    
    var isMatch: Bool {
        if case .match = self {
            return true
        }
        return false
    }
    
    var color: Color {
        switch self {
        case .match:
            return .green
        case .mismatch:
            return .red
        case .unavailable:
            return .gray
        }
    }
}

/// Comparison between analysis and Spotify reference
struct TrackComparison: Identifiable {
    var id: String { "\(testType?.rawValue ?? "unknown")|\(song)|\(artist)" }
    
    let testType: ABCDTestType?
    let song: String
    let artist: String
    
    // Analysis results
    let analyzedBPM: Int?
    let analyzedKey: String?
    
    // Spotify reference
    let spotifyBPM: Int?
    let spotifyKey: String?
    
    // Comparison results
    let bpmMatch: MetricMatch
    let keyMatch: MetricMatch
    
    var overallMatch: Bool {
        bpmMatch.isMatch && keyMatch.isMatch
    }
}

// MARK: - Test C Expected Reference (aligned with analyze_test_c_accuracy.py)

/// Expected BPM/key for a single Test C track.
struct TestCExpectedTrack {
    let bpm: Int
    let key: String
}

/// Canonical expectations for Test C (12 preview clips), using the same
/// targets as the Python `analyze_test_c_accuracy.py` script.
struct TestCExpectedReference {
    static let shared = TestCExpectedReference()
    
    private let expectations: [String: TestCExpectedTrack]
    
    private init() {
        expectations = [
            // Batch 1
            "Prisoner (feat. Dua Lipa)": TestCExpectedTrack(bpm: 128, key: "D# Minor"),
            "Forget You": TestCExpectedTrack(bpm: 127, key: "C"),
            "! (The Song Formerly Known As)": TestCExpectedTrack(bpm: 115, key: "B"),
            "1000x": TestCExpectedTrack(bpm: 112, key: "G# Major"),
            "2 Become 1": TestCExpectedTrack(bpm: 144, key: "F# Major"),
            "3AM": TestCExpectedTrack(bpm: 108, key: "G# Major"),
            
            // Batch 2
            "4ever": TestCExpectedTrack(bpm: 144, key: "F Minor"),
            "9 to 5": TestCExpectedTrack(bpm: 107, key: "F# Major"),
            "A Thousand Miles": TestCExpectedTrack(bpm: 149, key: "F# Major"),
            "A Thousand Years": TestCExpectedTrack(bpm: 132, key: "A# Major"),
            "A Whole New World (End Title)": TestCExpectedTrack(bpm: 114, key: "A Major"),
            "About Damn Time": TestCExpectedTrack(bpm: 111, key: "D# Minor"),
        ]
    }
    
    func expected(forSongTitle title: String) -> TestCExpectedTrack? {
        expectations[title]
    }
}

/// Utilities for comparing analysis results with Spotify reference
class ComparisonEngine {
    
    private enum MusicalMode: String {
        case major
        case minor
        case mixolydian
        case dorian
        case lydian
        case phrygian
        case locrian
    }
    
    /// Compare BPM with tolerance and octave detection
    static func compareBPM(analyzed: Int?, spotify: Int?) -> MetricMatch {
        guard let analyzed = analyzed, let spotify = spotify else {
            return .unavailable
        }

        let analyzedD = Double(analyzed)
        let spotifyD = Double(spotify)
        // Allow small relative tolerance; keep a floor of 3 BPM.
        let tolerance = max(3.0, spotifyD * 0.05)
        func within(_ candidate: Double) -> Bool {
            abs(analyzedD - candidate) <= tolerance
        }
        
        // Exact match within tolerance (±3 BPM)
        if within(spotifyD) {
            return .match
        }
        
        // Check for octave errors (half/double BPM)
        let halfSpotify = spotifyD / 2
        let doubleSpotify = spotifyD * 2
        
        // Half BPM (within tolerance)
        if within(halfSpotify) {
            return .match  // Still considered a match (common octave error)
        }
        
        // Double BPM (within tolerance)
        if within(doubleSpotify) {
            return .match  // Still considered a match (common octave error)
        }
        
        // No match
        return .mismatch(
            expected: "\(spotify)",
            actual: "\(analyzed)"
        )
    }
    
    /// Compare musical keys with enharmonic equivalents
    static func compareKey(analyzed: String?, reference: String?) -> MetricMatch {
        guard
            let analyzedRaw = analyzed?.trimmingCharacters(in: .whitespacesAndNewlines),
            let referenceRaw = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
            let parsedAnalyzed = parseKey(analyzedRaw),
            let parsedReference = parseKey(referenceRaw)
        else {
            return .unavailable
        }

        if keysEquivalent(parsedAnalyzed, parsedReference) {
            return .match
        }

        return .mismatch(
            expected: referenceRaw,
            actual: analyzedRaw
        )
    }
    
    /// Parsed canonical representation of a key.
    private struct ParsedKey: Equatable {
        let pitchClass: Int   // 0–11
        let mode: MusicalMode // "major", "minor", "mixolydian", etc.
    }
    
    /// Determine if two parsed keys share the same pitch material (exact, relative, or modal equivalence).
    private static func keysEquivalent(_ lhs: ParsedKey, _ rhs: ParsedKey) -> Bool {
        if lhs == rhs {
            return true
        }
        
        // Relative major/minor: major tonic is +3 semitones above its relative minor.
        if (lhs.mode == .major && rhs.mode == .minor) || (lhs.mode == .minor && rhs.mode == .major) {
            let majorRoot = lhs.mode == .major ? lhs.pitchClass : rhs.pitchClass
            let minorRoot = lhs.mode == .minor ? lhs.pitchClass : rhs.pitchClass
            if (majorRoot - minorRoot + 12) % 12 == 3 {
                return true
            }
        }
        
        // Mixolydian on the dominant shares the pitch set of the major scale a fourth above.
        if (lhs.mode == .mixolydian && rhs.mode == .major && (lhs.pitchClass + 5) % 12 == rhs.pitchClass) ||
            (rhs.mode == .mixolydian && lhs.mode == .major && (rhs.pitchClass + 5) % 12 == lhs.pitchClass) {
            return true
        }
        
        return false
    }
    
    /// Convert a key string into a canonical pitch class + mode, handling enharmonic spellings.
    private static func parseKey(_ key: String) -> ParsedKey? {
        var cleaned = key.lowercased()
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard !cleaned.isEmpty else { return nil }

        let modeTokens: [(String, MusicalMode)] = [
            ("mixolydian", .mixolydian),
            ("mixo", .mixolydian),
            ("lydian", .lydian),
            ("dorian", .dorian),
            ("phrygian", .phrygian),
            ("locrian", .locrian),
            ("aeolian", .minor),
            ("minor", .minor),
            ("min", .minor),
            ("ionian", .major),
            ("major", .major),
            ("maj", .major)
        ]
        
        var mode: MusicalMode = .major
        for (token, tokenMode) in modeTokens {
            if cleaned.contains(token) {
                mode = tokenMode
                break
            }
        }
        if mode == .major && cleaned.hasSuffix("m") {
            mode = .minor
        }

        // Strip mode markers to isolate the tonic spelling
        for (token, _) in modeTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        if cleaned.hasSuffix("m") { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Drop any non-note/accidental/slash characters (e.g., metadata noise)
        cleaned = cleaned.replacingOccurrences(
            of: "[^a-g#/xb]+",
            with: "",
            options: .regularExpression
        )
        guard !cleaned.isEmpty else { return nil }

        // Handle compound spellings like "D#/Eb" by trying each side until one parses.
        for token in cleaned.split(separator: "/") {
            if let pitch = pitchClass(for: String(token)) {
                return ParsedKey(pitchClass: pitch, mode: mode)
            }
        }
        // Fallback: grab first note-like token (handles ellipses or other noise)
        if let match = cleaned.range(of: "[a-gA-G][#bx]*", options: .regularExpression) {
            let token = String(cleaned[match])
            if let pitch = pitchClass(for: token) {
                return ParsedKey(pitchClass: pitch, mode: mode)
            }
        }
        return nil
    }

    /// Map a note token to its pitch class (supports double-sharps/flats and uppercase).
    private static func pitchClass(for token: String) -> Int? {
        let lowered = token.lowercased()
        guard let first = lowered.first else { return nil }
        let baseMap: [Character: Int] = [
            "c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11
        ]
        guard var pitch = baseMap[first] else { return nil }
        for accidental in lowered.dropFirst() {
            switch accidental {
            case "#":
                pitch += 1
            case "b":
                pitch -= 1
            case "x":  // Double-sharp shorthand
                pitch += 2
            default:
                return nil
            }
        }
        let normalized = pitch % 12
        return normalized >= 0 ? normalized : normalized + 12
    }
    
    /// Create a comparison for a single track
    static func compareTrack(
        analysis: AnalysisResult,
        spotifyReference: SpotifyTrack?,
        testType: ABCDTestType? = nil
    ) -> TrackComparison {
        // Start from raw Spotify reference values
        var expectedBPM = spotifyReference?.bpm
        var expectedKey = spotifyReference?.key
        
        // For Test C (12 preview clips), align expectations with the
        // Python analysis script (analyze_test_c_accuracy.py), which
        // uses curated tonic keys and BPMs instead of raw Spotify keys.
        if testType == .testC {
            if let override = TestCExpectedReference.shared.expected(forSongTitle: analysis.song) {
                expectedBPM = override.bpm
                expectedKey = override.key
            }
        }
        
        let bpmMatch = compareBPM(
            analyzed: analysis.bpm,
            spotify: expectedBPM
        )
        
        let keyMatch = compareKey(
            analyzed: analysis.key,
            reference: expectedKey
        )
        
        return TrackComparison(
            testType: testType,
            song: analysis.song,
            artist: spotifyReference?.artist ?? analysis.artist,
            analyzedBPM: analysis.bpm,
            analyzedKey: analysis.key,
            spotifyBPM: expectedBPM,
            spotifyKey: expectedKey,
            bpmMatch: bpmMatch,
            keyMatch: keyMatch
        )
    }
    
    /// Create comparisons for a batch of analysis results
    static func compareResults(
        analyses: [AnalysisResult],
        testType: ABCDTestType? = nil
    ) -> [TrackComparison] {
        let spotifyData = SpotifyReferenceData.shared
        
        return analyses.map { analysis in
            let spotifyRef = spotifyData.findTrack(
                song: analysis.song,
                artist: analysis.artist
            )
            
            // Debug logging
            if spotifyRef == nil {
                print("⚠️ No Spotify match for: '\(analysis.song)' by '\(analysis.artist)'")
            } else {
                print("✅ Matched '\(analysis.song)' -> Spotify: '\(spotifyRef!.song)' by '\(spotifyRef!.artist)'")
            }
            
            return compareTrack(
                analysis: analysis,
                spotifyReference: spotifyRef,
                testType: testType
            )
        }
    }
}
