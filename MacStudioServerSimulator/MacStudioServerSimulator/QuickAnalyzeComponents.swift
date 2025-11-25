//
//  QuickAnalyzeComponents.swift
//  MacStudioServerSimulator
//
//  Supporting models and cards for Quick Analyze UI.
//

import SwiftUI

struct DropErrorEntry: Identifiable {
    let id = UUID()
    let fileName: String
    let message: String
}

struct QuickAnalyzeResultEntry: Identifiable {
    let id = UUID()
    let fileName: String
    let result: MacStudioServerManager.AnalysisResult
}

struct AnalysisResultSummary: View {
    let result: MacStudioServerManager.AnalysisResult
    let fileName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(result.cached ? "Cached result" : "Fresh analysis")
                        .font(.caption)
                        .foregroundColor(result.cached ? .secondary : .green)
                }
                Spacer()
                Image(systemName: result.cached ? "internaldrive" : "bolt.fill")
                    .foregroundColor(result.cached ? .secondary : .green)
            }
            
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    AnalysisMetricCard(title: "BPM", value: String(format: "%.1f", result.bpm), icon: "metronome")
                    AnalysisMetricCard(title: "Confidence", value: percentageString(result.bpmConfidence), icon: "target")
                }
                GridRow {
                    AnalysisMetricCard(title: "Key", value: result.key.isEmpty ? "Unknown" : result.key, icon: "music.note")
                    AnalysisMetricCard(title: "Energy", value: percentageString(result.energy), icon: "bolt.fill")
                }
                GridRow {
                    AnalysisMetricCard(title: "Danceability", value: percentageString(result.danceability), icon: "figure.dance")
                    AnalysisMetricCard(title: "Acousticness", value: percentageString(result.acousticness), icon: "ear.fill")
                }
                GridRow {
                    AnalysisMetricCard(title: "Brightness", value: String(format: "%.0f Hz", result.spectralCentroid), icon: "sun.max.fill")
                    if let timeSignature = result.timeSignature {
                        AnalysisMetricCard(title: "Time Signature", value: timeSignature, icon: "textformat.123")
                    }
                }
                GridRow {
                    if let valence = result.valence {
                        AnalysisMetricCard(title: "Valence", value: percentageString(valence), icon: "face.smiling")
                    }
                    if let mood = result.mood {
                        AnalysisMetricCard(title: "Mood", value: mood.capitalized, icon: "theatermasks")
                    }
                }
                GridRow {
                    if let loudness = result.loudness {
                        AnalysisMetricCard(title: "Loudness", value: String(format: "%.1f dB", loudness), icon: "speaker.wave.3.fill")
                    }
                    if let range = result.dynamicRange {
                        AnalysisMetricCard(title: "Dynamic Range", value: String(format: "%.1f dB", range), icon: "slider.horizontal.3")
                    }
                }
                GridRow {
                    if let silence = result.silenceRatio {
                        AnalysisMetricCard(title: "Silence Ratio", value: percentageString(silence), icon: "waveform.slash")
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.2))
        )
    }
    
    private func percentageString(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

struct AnalysisMetricCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

