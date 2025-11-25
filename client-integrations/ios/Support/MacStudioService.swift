//
//  MacStudioService.swift
//  repapp
//
//  Created on 27/10/2025.
//  Service layer for Mac Studio Audio Analysis Server integration
//

import Foundation

/// Service for communicating with Mac Studio Audio Analysis Server
class MacStudioService {
    
    // MARK: - Configuration
    
    static let shared = MacStudioService()
    
    private var baseURL: String {
        #if targetEnvironment(simulator)
        // Use explicit IPv4 address to avoid IPv6 connection issues
        return "http://127.0.0.1:5050"
        #else
        // For device: use Mac's actual hostname (Bonjour/mDNS)
        // If this doesn't work, user should update to their Mac's actual hostname
        // Run `hostname` in Terminal on Mac to find it
        return "http://Costass-Mac-Studio.local:5050"
        #endif
    }
    
    // Fallback URLs to try if primary fails
    private let fallbackURLs: [String] = [
        "http://192.168.4.247:5050",  // Direct IP (fastest if on same network)
        "http://Costass-Mac-Studio.local:5050",  // mDNS hostname
        "http://127.0.0.1:5050"  // localhost (works if on same machine)
    ]
    
    // Persist the last URL that succeeded so we prefer it on future requests
    private let resolvedURLQueue = DispatchQueue(label: "app.songwise.macstudio.baseurl", qos: .utility)
    private var resolvedBaseURLValue: String?
    
    private func preferredBaseURLs() -> [String] {
        var urls: [String] = []
        
        resolvedURLQueue.sync {
            if let resolved = resolvedBaseURLValue {
                urls.append(resolved)
            }
        }
        
        // Add the platform-specific default followed by the static fallbacks
        for candidate in [baseURL] + fallbackURLs {
            if !urls.contains(candidate) {
                urls.append(candidate)
            }
        }
        
        return urls
    }
    
    private func updateResolvedBaseURL(_ url: String) {
        resolvedURLQueue.async {
            self.resolvedBaseURLValue = url
        }
    }
    
    // MARK: - Models
    
    struct AnalysisRequest: Codable {
        let url: String
        let title: String
        let artist: String
    }
    
    struct AnalysisResult: Codable {
        let bpm: Double
        let bpmConfidence: Double
        let key: String
        let keyConfidence: Double
        let energy: Double
        let danceability: Double
        let acousticness: Double
        let spectralCentroid: Double
        let cached: Bool
        let analysisDuration: Double?
        let analyzedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case bpm
            case bpmConfidence = "bpm_confidence"
            case key
            case keyConfidence = "key_confidence"
            case energy, danceability, acousticness
            case spectralCentroid = "spectral_centroid"
            case cached
            case analysisDuration = "analysis_duration"
            case analyzedAt = "analyzed_at"
        }
        
        // MARK: - NaN-Safe Accessors (Critical for iPad stability)
        
        /// Safe BPM value that never returns NaN - returns 0 if invalid
        var safeBPM: Double {
            guard !bpm.isNaN, bpm.isFinite, bpm > 0, bpm < 500 else { return 0 }
            return bpm
        }
        
        /// Safe confidence values (0-1 range)
        var safeBPMConfidence: Double {
            guard !bpmConfidence.isNaN, bpmConfidence.isFinite else { return 0 }
            return max(0, min(1, bpmConfidence))
        }
        
        var safeKeyConfidence: Double {
            guard !keyConfidence.isNaN, keyConfidence.isFinite else { return 0 }
            return max(0, min(1, keyConfidence))
        }
        
        /// Safe audio features (0-1 range)
        var safeEnergy: Double {
            guard !energy.isNaN, energy.isFinite else { return 0 }
            return max(0, min(1, energy))
        }
        
        var safeDanceability: Double {
            guard !danceability.isNaN, danceability.isFinite else { return 0 }
            // Clamp to 0-1 range (server may return negative values from librosa)
            return max(0, min(1, danceability))
        }
        
        var safeAcousticness: Double {
            guard !acousticness.isNaN, acousticness.isFinite else { return 0 }
            return max(0, min(1, acousticness))
        }
        
        /// Validate all numeric fields are valid (not NaN or infinite)
        /// Note: Some values like danceability may be negative (librosa quirk), which is OK
        var isValid: Bool {
            return !bpm.isNaN && bpm.isFinite && bpm > 0 &&
                   !bpmConfidence.isNaN && bpmConfidence.isFinite &&
                   !keyConfidence.isNaN && keyConfidence.isFinite &&
                   !energy.isNaN && energy.isFinite &&
                   !danceability.isNaN && danceability.isFinite &&
                   !acousticness.isNaN && acousticness.isFinite
        }
    }
