//
//  ServerManagementCacheTab.swift
//

#if os(macOS)

import SwiftUI
import AppKit

struct CacheTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @Binding var searchQuery: String
    @Binding var showingClearAlert: Bool
    @State private var isTitleAscending = true
    private let autoRefreshIntervalNanoseconds: UInt64 = 30 * 1_000_000_000
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by title or artist", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit { performSearch() }
                    
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            Task { await manager.fetchCachedAnalyses() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                Text("\(manager.cachedAnalyses.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    isTitleAscending.toggle()
                } label: {
                    Label(isTitleAscending ? "Title A→Z" : "Title Z→A", systemImage: "textformat")
                }
                .buttonStyle(.bordered)
                
                Button {
                    Task { await manager.fetchCachedAnalyses() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button {
                    showingClearAlert = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if manager.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading cache…")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if manager.cachedAnalyses.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No cached analyses")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Analyses will appear here once songs are processed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedAnalyses) { analysis in
                            CachedAnalysisRow(analysis: analysis, manager: manager)
                                .id(analysis.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
        }
        .alert("Clear All Cache?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task { await manager.clearAllCache() }
            }
        } message: {
            Text("This will permanently delete all \(manager.cachedAnalyses.count) cached analyses. This action cannot be undone.")
        }
        .task(id: manager.isServerRunning) {
            await autoRefreshCache()
        }
    }
    
    private func performSearch() {
        Task {
            if searchQuery.isEmpty {
                await manager.fetchCachedAnalyses()
            } else {
                await manager.searchCache(query: searchQuery)
            }
        }
    }
    
    private var sortedAnalyses: [CachedAnalysis] {
        manager.cachedAnalyses.sorted { first, second in
            let comparison = first.title.localizedCaseInsensitiveCompare(second.title)
            if comparison == .orderedSame {
                return first.id < second.id
            }
            return isTitleAscending ? comparison != .orderedDescending : comparison == .orderedDescending
        }
    }
    
    @MainActor
    private func autoRefreshCache() async {
        guard manager.isServerRunning else { return }
        let shouldShowLoading = manager.cachedAnalyses.isEmpty
        if searchQuery.isEmpty {
            await manager.fetchCachedAnalyses(showLoadingIndicator: shouldShowLoading)
        } else {
            await manager.searchCache(query: searchQuery, showLoadingIndicator: shouldShowLoading)
        }
        
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: autoRefreshIntervalNanoseconds)
            } catch {
                break
            }
            
            guard manager.isServerRunning else { break }
            if searchQuery.isEmpty {
                await manager.fetchCachedAnalyses(showLoadingIndicator: false)
            } else {
                await manager.searchCache(query: searchQuery, showLoadingIndicator: false)
            }
        }
    }
}

#endif

struct CachedAnalysisRow: View {
    let analysis: CachedAnalysis
    @ObservedObject var manager: MacStudioServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            highlightRow
            Divider()
            metrics
            Divider()
            actions
        }
        .padding(16)
        .background(.thinMaterial)
        .cornerRadius(12)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
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
                        .font(.title3)
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
            if analysis.userVerified {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            Spacer()
        }
    }
    
    private var metrics: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let keyConfidence = analysis.keyConfidence {
                MetricRow(label: "Key Confidence", value: percentage(keyConfidence))
            }
            if let danceability = analysis.danceability {
                MetricRow(label: "Danceability", value: percentage(danceability))
            }
            if let acousticness = analysis.acousticness {
                MetricRow(label: "Acousticness", value: percentage(acousticness))
            }
            if let spectral = analysis.spectralCentroid {
                MetricRow(label: "Brightness", value: String(format: "%.0f Hz", spectral))
            }
        }
        .font(.caption)
    }
    
    private var actions: some View {
        HStack {
            Button {
                Task { await manager.deleteFromCache(id: analysis.id) }
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
            Spacer()
            
            Button {
                Task {
                    let url = try await manager.exportCache(limit: 1, offset: 0)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
        }
    }
    
    private func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}
