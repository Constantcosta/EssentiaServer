//
//  ServerManagementView.swift
//  repapp
//
//  Created on 29/10/2025.
//

import SwiftUI

#if os(macOS)

// SUMMARY
// macOS-only dashboard for the Mac Studio analysis server: status header,
// overview stats, cache browser, and log placeholder with controls to refresh,
// restart, or fetch cache entries via MacStudioServerManager.

struct ServerManagementView: View {
    @StateObject private var manager = MacStudioServerManager()
    @State private var selectedTab = 0
    @State private var searchQuery = ""
    @State private var showingClearAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with server status
            ServerStatusHeader(manager: manager)
            
            Divider()
            
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Label("Overview", systemImage: "chart.bar.fill").tag(0)
                Label("Cache", systemImage: "tray.full.fill").tag(1)
                Label("Logs", systemImage: "doc.text.fill").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    OverviewTab(manager: manager)
                case 1:
                    CacheTab(manager: manager, searchQuery: $searchQuery, showingClearAlert: $showingClearAlert)
                case 2:
                    LogsTab()
                default:
                    OverviewTab(manager: manager)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await manager.checkServerStatus()
            if manager.isServerRunning {
                await manager.fetchServerStats()
            }
        }
    }
}

// MARK: - Server Status Header

struct ServerStatusHeader: View {
    @ObservedObject var manager: MacStudioServerManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isServerRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isServerRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                    Text("Port 5050")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Error message
            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
            
            // Control buttons
            HStack(spacing: 8) {
                if manager.isServerRunning {
                    Button(action: {
                        Task {
                            await manager.fetchServerStats()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(manager.isLoading)
                    
                    Button(action: {
                        Task {
                            await manager.restartServer()
                        }
                    }) {
                        Label("Restart", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(manager.isLoading)
                    
                    Button(action: {
                        Task {
                            await manager.stopServer()
                        }
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                    .disabled(manager.isLoading)
                } else {
                    Button(action: {
                        Task {
                            await manager.startServer()
                        }
                    }) {
                        Label("Start Server", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isLoading)
                }
                
                if manager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @State private var dbInfo: (size: String, location: String, itemCount: Int) = ("", "", 0)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Statistics
                if let stats = manager.serverStats {
                    VStack(spacing: 16) {
                        Text("Server Statistics")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCard(title: "Total Analyses", value: "\(stats.totalAnalyses)", icon: "waveform", color: .blue)
                            StatCard(title: "Cache Hits", value: "\(stats.cacheHits)", icon: "checkmark.circle.fill", color: .green)
                            StatCard(title: "Cache Misses", value: "\(stats.cacheMisses)", icon: "xmark.circle.fill", color: .orange)
                            StatCard(title: "Hit Rate", value: stats.cacheHitRate, icon: "chart.bar.fill", color: .purple)
                        }
                        
                        Text("Last Updated: \(formatDate(stats.lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                Divider()
                
                // Database Info
                VStack(alignment: .leading, spacing: 16) {
                    Text("Database Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Location", value: dbInfo.location)
                        InfoRow(label: "Size", value: dbInfo.size)
                        InfoRow(label: "Cached Items", value: "\(dbInfo.itemCount)")
                    }
                    
                    Button(action: {
                        NSWorkspace.shared.selectFile(dbInfo.location, inFileViewerRootedAtPath: "")
                    }) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding()
        }
        .task {
            if manager.isServerRunning {
                await manager.fetchServerStats()
                dbInfo = await manager.getDatabaseInfo()
            }
        }
        .onChange(of: manager.isServerRunning) { _, isRunning in
            if isRunning {
                Task {
                    await manager.fetchServerStats()
                    dbInfo = await manager.getDatabaseInfo()
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Cache Tab

struct CacheTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @Binding var searchQuery: String
    @Binding var showingClearAlert: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar and controls
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by title or artist", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task {
                                if searchQuery.isEmpty {
                                    await manager.fetchCachedAnalyses()
                                } else {
                                    await manager.searchCache(query: searchQuery)
                                }
                            }
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            Task {
                                await manager.fetchCachedAnalyses()
                            }
                        }) {
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
                
                Button(action: {
                    Task {
                        await manager.fetchCachedAnalyses()
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    showingClearAlert = true
                }) {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Cache list
            if manager.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading cache...")
                        .foregroundColor(.secondary)
                        .padding(.top)
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
                    Text("Analyses will appear here once songs are processed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(manager.cachedAnalyses) { analysis in
                        CachedAnalysisRow(analysis: analysis, manager: manager)
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Clear All Cache?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task {
                    await manager.clearAllCache()
                }
            }
        } message: {
            Text("This will permanently delete all \(manager.cachedAnalyses.count) cached analyses. This action cannot be undone.")
        }
        .task {
            if manager.isServerRunning {
                await manager.fetchCachedAnalyses()
            }
        }
    }
}

// MARK: - Logs Tab

struct LogsTab: View {
    @State private var logContent = "Loading logs..."
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .onChange(of: autoRefresh) { _, enabled in
                        if enabled {
                            startAutoRefresh()
                        } else {
                            stopAutoRefresh()
                        }
                    }
                
                Spacer()
                
                Button(action: {
                    loadLogs()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logContent, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                Text(logContent)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .task {
            loadLogs()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    private func loadLogs() {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/AudioAnalysisCache/server.log")
        
        if let content = try? String(contentsOf: logPath) {
            let lines = content.components(separatedBy: .newlines)
            logContent = lines.suffix(200).joined(separator: "\n")
        } else {
            logContent = "No logs available. Start the server to generate logs."
        }
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            loadLogs()
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .blue
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
            
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

struct CachedAnalysisRow: View {
    let analysis: CachedAnalysis
    @ObservedObject var manager: MacStudioServerManager
    @State private var showingDetail = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            
            HStack(spacing: 16) {
                if let key = analysis.key {
                    Label(key, systemImage: "music.note")
                        .font(.caption)
                }
                
                if let energy = analysis.energy {
                    Label(String(format: "⚡️ %.0f%%", energy * 100), systemImage: "bolt.fill")
                        .font(.caption)
                }
                
                if let danceability = analysis.danceability {
                    Label(String(format: "💃 %.0f%%", danceability * 100), systemImage: "figure.dance")
                        .font(.caption)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        showingDetail.toggle()
                    }
                }) {
                    Text(showingDetail ? "Hide Details" : "Show Details")
                        .font(.caption)
                }
            }
            
            if showingDetail {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    if let acousticness = analysis.acousticness {
                        HStack {
                            Text("Acousticness:")
                            Spacer()
                            Text(String(format: "%.0f%%", acousticness * 100))
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                    }
                    
                    if let spectral = analysis.spectralCentroid {
                        HStack {
                            Text("Brightness:")
                            Spacer()
                            Text(String(format: "%.0f Hz", spectral))
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                    }
                    
                    HStack {
                        Text("Analyzed:")
                        Spacer()
                        Text(formatTimestamp(analysis.analyzedAt))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            await manager.deleteFromCache(id: analysis.id)
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
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
}

#Preview {
    ServerManagementView()
        .frame(width: 900, height: 600)
}

#endif
