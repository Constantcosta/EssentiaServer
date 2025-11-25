//
//  ServerManagementQuickAnalyze.swift
//  MacStudioServerSimulator
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

typealias AudioAnalysisError = MacStudioServerManager.AudioAnalysisError

struct AudioDropAnalyzer: View {
    @ObservedObject var manager: MacStudioServerManager
    @State private var isTargeted = false
    @State private var isAnalyzing = false
    @State private var lastFileName: String = ""
    @State private var batchTotal = 0
    @State private var batchIndex = 0
    
    private let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "flac", "aac", "caf"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            dropZone
            actions
            authorizedFolderStatus
            history
            errors
        }
    }
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Quick Analyze", systemImage: "waveform.and.mic")
                .font(.title3)
                .fontWeight(.bold)
            
            Spacer()
            
            if let latestEntry = manager.quickAnalyzeHistory.first {
                Label(latestEntry.result.cached ? "Served from cache" : "Fresh analysis",
                      systemImage: latestEntry.result.cached ? "internaldrive" : "bolt.fill")
                .font(.caption)
                .foregroundColor(latestEntry.result.cached ? .secondary : .green)
                .help("Last analyzed: \(latestEntry.fileName)")
            }
        }
    }
    
    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isTargeted ? Color.accentColor : Color.gray.opacity(0.4),
                          style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [] : [8, 6]))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .textBackgroundColor))
            )
            .frame(maxWidth: .infinity, minHeight: 160)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(manager.isServerRunning ? .accentColor : .secondary)
                    
                    Text(manager.isServerRunning ? "Drop audio files (.m4a, .mp3, .wav, .flac)" : "Start the server to analyze files")
                        .font(.headline)
                    
                    Text("Files stay on your Mac—just a quick POST to /analyze_data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                handleDropFromProviders(providers)
            }
            .onTapGesture {
                if manager.isServerRunning {
                    openFilePicker()
                } else {
                    let message = AudioAnalysisError.serverOffline.errorDescription ?? "Start the Python server before analyzing."
                    manager.quickAnalyzeErrors = [DropErrorEntry(fileName: "Quick Analyze", message: message)]
                }
            }
            .overlay {
                if isAnalyzing {
                    Color.black.opacity(0.05)
                        .cornerRadius(12)
                }
            }
    }
    
    private var actions: some View {
        HStack(spacing: 12) {
            Button { openFilePicker() } label: {
                Label("Choose File…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(isAnalyzing || !manager.isServerRunning)
            
            Text("Analyzes full tracks and auto-samples 15s windows for extra accuracy. Select multiple files to batch import.")
                .font(.caption)
                .foregroundColor(.secondary)
            
#if os(macOS)
            Button {
                manager.promptForAuthorizedFolder()
            } label: {
                Label(manager.authorizedFolderDisplayName == nil ? "Link Folder…" : "Change Folder…", systemImage: manager.authorizedFolderDisplayName == nil ? "externaldrive.badge.plus" : "externaldrive.badge.checkmark")
            }
            .buttonStyle(.bordered)
            .disabled(isAnalyzing)
#endif
        }
    }
    
    private var authorizedFolderStatus: some View {
#if os(macOS)
        Text(manager.authorizedFolderDisplayName == nil ? "Not linked to a folder yet. Configure access if you want to save quick analyze results automatically." : "Authorized folder: \(manager.authorizedFolderDisplayName ?? "")")
            .font(.caption2)
            .foregroundColor(.secondary)
#else
        EmptyView()
#endif
    }
    
    private var history: some View {
        Group {
            if !manager.quickAnalyzeHistory.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Analyses")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(manager.quickAnalyzeHistory) { entry in
                                AnalysisResultSummary(result: entry.result, fileName: entry.fileName)
                                    .frame(width: 320)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        manager.quickAnalyzeHistory = []
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    private var errors: some View {
        Group {
            if !manager.quickAnalyzeErrors.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Errors")
                        .font(.headline)
                        .foregroundColor(.red)
                    ForEach(manager.quickAnalyzeErrors) { error in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.fileName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(error.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.05))
                        )
                    }
                    Button {
                        manager.quickAnalyzeErrors = []
                    } label: {
                        Label("Dismiss Errors", systemImage: "checkmark")
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    private func handleDropFromProviders(_ providers: [NSItemProvider]) -> Bool {
        let typeIdentifier = "public.file-url"
        var found = false
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                found = true
                group.enter()
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            urls.append(url)
                            group.leave()
                        }
                    } else {
                        DispatchQueue.main.async {
                            group.leave()
                        }
                    }
                }
            }
        }
        
        guard found else { return false }
        
        group.notify(queue: .main) {
            _ = handleDrop(urls)
        }
        
        return true
    }
    
    private func handleDrop(_ urls: [URL]) -> Bool {
        let accepted = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard !accepted.isEmpty else {
            manager.quickAnalyzeErrors = [DropErrorEntry(fileName: "Import", message: "Unsupported file type. Use \(supportedExtensions.joined(separator: ", ")).")]
            return false
        }
        analyzeFiles(accepted)
        return true
    }
    
    private func analyzeFiles(_ urls: [URL]) {
        isAnalyzing = true
        batchTotal = urls.count
        batchIndex = 0
        
        Task {
            for url in urls {
                batchIndex += 1
                lastFileName = url.lastPathComponent
                await manager.quickAnalyzeFile(url)
            }
            isAnalyzing = false
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK {
                analyzeFiles(panel.urls)
            }
        }
    }
}

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
