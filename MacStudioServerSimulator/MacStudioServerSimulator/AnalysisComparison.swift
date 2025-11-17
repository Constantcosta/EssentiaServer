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
    var id: String { song + artist }
    
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

/// Utilities for comparing analysis results with Spotify reference
class ComparisonEngine {
    
    /// Compare BPM with tolerance and octave detection
    static func compareBPM(analyzed: Int?, spotify: Int?) -> MetricMatch {
        guard let analyzed = analyzed, let spotify = spotify else {
            return .unavailable
        }
        
        // Exact match within tolerance (±3 BPM)
        if abs(analyzed - spotify) <= 3 {
            return .match
        }
        
        // Check for octave errors (half/double BPM)
        let halfSpotify = spotify / 2
        let doubleSpotify = spotify * 2
        
        // Half BPM (within tolerance)
        if abs(analyzed - halfSpotify) <= 3 {
            return .match  // Still considered a match (common octave error)
        }
        
        // Double BPM (within tolerance)
        if abs(analyzed - doubleSpotify) <= 3 {
            return .match  // Still considered a match (common octave error)
        }
        
        // No match
        return .mismatch(
            expected: "\(spotify)",
            actual: "\(analyzed)"
        )
    }
    
    /// Compare musical keys with enharmonic equivalents
    static func compareKey(analyzed: String?, spotify: String?) -> MetricMatch {
        guard
            let analyzed = analyzed?.trimmingCharacters(in: .whitespacesAndNewlines),
            let spotify = spotify?.trimmingCharacters(in: .whitespacesAndNewlines),
            let normalizedAnalyzed = normalizeKey(analyzed),
            let normalizedSpotify = normalizeKey(spotify)
        else {
            return .unavailable
        }
        
        // Direct comparison first
        if normalizedAnalyzed == normalizedSpotify {
            return .match
        }
        
        // Check enharmonic equivalents (e.g., D# == Eb, G#/Ab == Ab)
        if areEnharmonicEquivalents(normalizedAnalyzed, normalizedSpotify) {
            return .match
        }
        
        return .mismatch(
            expected: spotify,
            actual: analyzed
        )
    }
    
    /// Normalize a key string into (note, mode). Returns nil if the input is empty.
    private static func normalizeKey(_ key: String) -> (note: String, mode: String)? {
        var cleaned = key.lowercased()
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        
        guard !cleaned.isEmpty else { return nil }
        
        // Detect mode by suffix/keyword, not by presence of the letter "m"
        var mode = "major"
        if cleaned.hasSuffix("m") {
            cleaned.removeLast()
            mode = "minor"
        }
        if cleaned.contains("minor") {
            cleaned = cleaned.replacingOccurrences(of: "minor", with: "")
            mode = "minor"
        }
        // Strip explicit "major"/"maj" noise
        cleaned = cleaned
            .replacingOccurrences(of: "major", with: "")
            .replacingOccurrences(of: "maj", with: "")
        
        // Handle slash notation (e.g., "D#/Eb" or "G#/Ab") - take first part
        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex])
        }
        
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !cleaned.isEmpty else { return nil }
        
        return (note: cleaned, mode: mode)
    }
    
    /// Check if two normalized keys (note, mode) are enharmonic equivalents
    private static func areEnharmonicEquivalents(
        _ key1: (note: String, mode: String),
        _ key2: (note: String, mode: String)
    ) -> Bool {
        guard key1.mode == key2.mode else { return false }
        
        // Normalize both notes to a canonical form for comparison
        func normalizeNote(_ note: String) -> String {
            let note = note.lowercased()
            // Map all enharmonic equivalents to a canonical form (using sharps)
            let canonicalMap: [String: String] = [
                "c": "c", "b#": "c",
                "c#": "c#", "db": "c#",
                "d": "d",
                "d#": "d#", "eb": "d#",
                "e": "e", "fb": "e",
                "f": "f", "e#": "f",
                "f#": "f#", "gb": "f#",
                "g": "g",
                "g#": "g#", "ab": "g#",
                "a": "a",
                "a#": "a#", "bb": "a#",
                "b": "b", "cb": "b"
            ]
            return canonicalMap[note] ?? note
        }
        
        let canonical1 = normalizeNote(key1.note)
        let canonical2 = normalizeNote(key2.note)
        
        return canonical1 == canonical2
    }
    
    /// Create a comparison for a single track
    static func compareTrack(
        analysis: AnalysisResult,
        spotifyReference: SpotifyTrack?
    ) -> TrackComparison {
        let bpmMatch = compareBPM(
            analyzed: analysis.bpm,
            spotify: spotifyReference?.bpm
        )
        
        let keyMatch = compareKey(
            analyzed: analysis.key,
            spotify: spotifyReference?.key
        )
        
        return TrackComparison(
            song: analysis.song,
            artist: spotifyReference?.artist ?? analysis.artist,
            analyzedBPM: analysis.bpm,
            analyzedKey: analysis.key,
            spotifyBPM: spotifyReference?.bpm,
            spotifyKey: spotifyReference?.key,
            bpmMatch: bpmMatch,
            keyMatch: keyMatch
        )
    }
    
    /// Create comparisons for a batch of analysis results
    static func compareResults(
        analyses: [AnalysisResult]
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
                spotifyReference: spotifyRef
            )
        }
    }
}
