//
//  ServerTestView.swift
//  MacStudioServerSimulator
//
//  Test view for analyzing audio and viewing results
//

import SwiftUI

struct ServerTestView: View {
    @EnvironmentObject var serverManager: MacStudioServerManager
    @State private var testURL = "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/test.m4a"
    @State private var songTitle = "Test Song"
    @State private var artist = "Test Artist"
    @State private var analysisResult: AnalysisResult?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section("Audio Input") {
                TextField("Preview URL", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                
                TextField("Song Title", text: $songTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Artist", text: $artist)
                    .textFieldStyle(.roundedBorder)
                
                Button("Analyze Audio") {
                    Task {
                        await analyzeAudio()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing || !serverManager.isServerRunning)
            }
            
            if isAnalyzing {
                Section {
                    HStack {
                        ProgressView()
                        Text("Analyzing...")
                    }
                }
            }
            
            if let error = errorMessage {
                Section("Error") {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            if let result = analysisResult {
                Section("Core Analysis Results") {
                    LabeledContent("BPM", value: String(format: "%.1f", result.bpm))
                    LabeledContent("BPM Confidence", value: String(format: "%.0f%%", result.bpmConfidence * 100))
                    LabeledContent("Key", value: result.key)
                    LabeledContent("Energy", value: String(format: "%.2f", result.energy))
                    LabeledContent("Danceability", value: String(format: "%.2f", result.danceability))
                    LabeledContent("Acousticness", value: String(format: "%.2f", result.acousticness))
                }
                
                Section("Phase 1 Features") {
                    if let timeSignature = result.timeSignature {
                        LabeledContent("Time Signature", value: timeSignature)
                    }
                    if let valence = result.valence {
                        LabeledContent("Valence", value: String(format: "%.2f", valence))
                    }
                    if let mood = result.mood {
                        LabeledContent("Mood", value: mood.capitalized)
                    }
                    if let loudness = result.loudness {
                        LabeledContent("Loudness", value: String(format: "%.1f dB", loudness))
                    }
                    if let dynamicRange = result.dynamicRange {
                        LabeledContent("Dynamic Range", value: String(format: "%.1f dB", dynamicRange))
                    }
                    if let silenceRatio = result.silenceRatio {
                        LabeledContent("Silence Ratio", value: String(format: "%.1f%%", silenceRatio * 100))
                    }
                }
                
                Section("Metadata") {
                    LabeledContent("Analysis Duration", value: String(format: "%.2f sec", result.analysisDuration))
                    LabeledContent("Cached", value: result.cached ? "Yes" : "No")
                }
            }
        }
        .navigationTitle("Audio Analysis Test")
    }
    
    private func analyzeAudio() async {
        isAnalyzing = true
        errorMessage = nil
        
        do {
            let result = try await serverManager.analyzeAudio(
                url: testURL,
                title: songTitle,
                artist: artist
            )
            analysisResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isAnalyzing = false
    }
}

struct Phase1FeaturesTestView: View {
    @EnvironmentObject var serverManager: MacStudioServerManager
    
    var body: some View {
        Form {
            Section("Phase 1 Features") {
                Text("Time Signature Detection")
                    .font(.headline)
                Text("Detects 3/4, 4/4, 5/4, etc.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Mood & Valence Estimation")
                    .font(.headline)
                Text("0-1 scale (sad to happy) + categories")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Loudness & Dynamic Range")
                    .font(.headline)
                Text("LUFS-like measurement in dB")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Silence Detection")
                    .font(.headline)
                Text("Ratio of silent frames")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Test Scenarios") {
                Button("Test Happy Song (Fast Major)") {
                    // Could add sample test here
                }
                
                Button("Test Sad Song (Slow Minor)") {
                    // Could add sample test here
                }
            }
        }
        .navigationTitle("Phase 1 Features")
    }
}

// MARK: - Models

struct AnalysisResult: Codable {
    let bpm: Double
    let bpmConfidence: Double
    let key: String
    let keyConfidence: Double
    let energy: Double
    let danceability: Double
    let acousticness: Double
    let spectralCentroid: Double
    let analysisDuration: Double
    let cached: Bool
    
    // Phase 1 features (optional for backward compatibility)
    let timeSignature: String?
    let valence: Double?
    let mood: String?
    let loudness: Double?
    let dynamicRange: Double?
    let silenceRatio: Double?
    
    enum CodingKeys: String, CodingKey {
        case bpm
        case bpmConfidence = "bpm_confidence"
        case key
        case keyConfidence = "key_confidence"
        case energy
        case danceability
        case acousticness
        case spectralCentroid = "spectral_centroid"
        case analysisDuration = "analysis_duration"
        case cached
        case timeSignature = "time_signature"
        case valence
        case mood
        case loudness
        case dynamicRange = "dynamic_range"
        case silenceRatio = "silence_ratio"
    }
}

#Preview {
    NavigationView {
        ServerTestView()
            .environmentObject(MacStudioServerManager())
    }
}
