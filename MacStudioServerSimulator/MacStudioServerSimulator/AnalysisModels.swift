//
//  AnalysisModels.swift
//  MacStudioServerSimulator
//
//  Shared analysis result models used across comparison and UI.
//

import Foundation
import SwiftUI

/// Result of analyzing a single track.
struct AnalysisResult {
    let song: String
    let artist: String
    let bpm: Int?
    let key: String?
    let success: Bool
    let duration: Double
}

/// Comparison result for a single metric.
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

/// Comparison between analysis and Spotify reference.
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

