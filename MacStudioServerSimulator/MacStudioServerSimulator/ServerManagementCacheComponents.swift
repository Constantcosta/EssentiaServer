//
//  ServerManagementCacheComponents.swift
//  MacStudioServerSimulator
//
//  Subviews for the cache tab list.
//

import SwiftUI
import AppKit

struct CachedAnalysisRow: View {
    let analysis: CachedAnalysis
    @ObservedObject var manager: MacStudioServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            highlightRow
            
            Divider()
            MetricsGrid(analysis: analysis)
                .padding(.top, 4)
            
            if hasManualOverrides {
                Divider()
                manualOverrides
            }
            
            Divider()
            footer
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.25))
        )
    }
    
    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.title)
                    .font(.headline)
                
                Text(analysis.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let bpm = analysis.bpm {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(bpm)) BPM")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    if let confidence = analysis.bpmConfidence {
                        Text(String(format: "%.0f%% confidence", confidence * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var highlightRow: some View {
        HStack(spacing: 16) {
            if let key = analysis.key {
                Label(key, systemImage: "music.note")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let energy = analysis.energy {
                Label(String(format: "⚡️ %.0f%%", energy * 100), systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let danceability = analysis.danceability {
                Label(String(format: "💃 %.0f%%", danceability * 100), systemImage: "figure.dance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if analysis.userVerified {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var manualOverrides: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let manualBpm = analysis.manualBpm {
                DetailRow(label: "Manual BPM", value: String(format: "%.1f", manualBpm))
            }
            
            if let manualKey = analysis.manualKey, !manualKey.isEmpty {
                DetailRow(label: "Manual Key", value: manualKey)
            }
            
            if let notes = analysis.bpmNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
               !notes.isEmpty {
                DetailRow(label: "Notes", value: notes)
            }
        }
    }
    
    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Preview URL", value: analysis.previewUrl, isMonospaced: true)
                .contextMenu {
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(analysis.previewUrl, forType: .string)
                    }
                }
            
            DetailRow(label: "Analyzed", value: formatTimestamp(analysis.analyzedAt))
            if let duration = analysis.analysisDuration {
                DetailRow(label: "Processing Time", value: String(format: "%.2f s", duration))
            }
            
            HStack {
                Button {
                    Task { await manager.deleteFromCache(id: analysis.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: NSHomeDirectory())
                            .appendingPathComponent("Music/AudioAnalysisCache")
                    )
                } label: {
                    Label("Open Cache Folder", systemImage: "folder")
                        .font(.caption)
                }
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return timestamp
    }

    private var hasManualOverrides: Bool {
        if analysis.manualBpm != nil { return true }
        if let manualKey = analysis.manualKey, !manualKey.isEmpty { return true }
        if let notes = analysis.bpmNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty { return true }
        return false
    }
}

private struct MetricsGrid: View {
    let analysis: CachedAnalysis
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            if let bpm = analysis.bpm {
                MetricCell(label: "BPM", value: String(format: "%.1f", bpm))
            }
            if let confidence = analysis.bpmConfidence {
                MetricCell(label: "BPM Confidence", value: percent(confidence))
            }
            if let key = analysis.key {
                MetricCell(label: "Key", value: key)
            }
            if let keyConf = analysis.keyConfidence {
                MetricCell(label: "Key Confidence", value: percent(keyConf))
            }
            if let energy = analysis.energy {
                MetricCell(label: "Energy", value: percent(energy))
            }
            if let dance = analysis.danceability {
                MetricCell(label: "Danceability", value: percent(dance))
            }
            if let acoustic = analysis.acousticness {
                MetricCell(label: "Acousticness", value: percent(acoustic))
            }
            if let spectral = analysis.spectralCentroid {
                MetricCell(label: "Brightness", value: String(format: "%.0f Hz", spectral))
            }
            if let signature = analysis.timeSignature, !signature.isEmpty {
                MetricCell(label: "Time Signature", value: signature)
            }
            if let valence = analysis.valence {
                MetricCell(label: "Valence", value: percent(valence))
            }
            if let mood = analysis.mood, !mood.isEmpty {
                MetricCell(label: "Mood", value: mood.capitalized)
            }
            if let loudness = analysis.loudness {
                MetricCell(label: "Loudness", value: String(format: "%.1f dB", loudness))
            }
            if let range = analysis.dynamicRange {
                MetricCell(label: "Dynamic Range", value: String(format: "%.1f dB", range))
            }
            if let silence = analysis.silenceRatio {
                MetricCell(label: "Silence Ratio", value: percent(silence))
            }
            if let duration = analysis.analysisDuration {
                MetricCell(label: "Analysis Duration", value: String(format: "%.2f s", duration))
            }
        }
        .font(.caption)
    }
    
    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced = false
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
            
            Spacer()
        }
    }
}

