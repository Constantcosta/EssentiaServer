//
//  ServerManagementOverviewTab.swift
//  MacStudioServerSimulator
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct OverviewTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @State private var dbInfo: (size: String, location: String, itemCount: Int) = ("", "", 0)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AudioDropAnalyzer(manager: manager)
                
                DiagnosticsPanel(manager: manager)
                
                Divider()
                
                if let stats = manager.serverStats {
                    VStack(spacing: 16) {
                        Text("Server Statistics")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCard(title: "Total Analyses", value: "\(stats.totalAnalyses)", icon: "waveform", color: .blue)
                            StatCard(title: "Cache Hits", value: "\(stats.cacheHits)", icon: "checkmark.circle.fill", color: .green)
                            StatCard(title: "Cache Misses", value: "\(stats.cacheMisses)", icon: "xmark.circle.fill", color: .orange)
                            StatCard(title: "Hit Rate", value: stats.cacheHitRateFormatted, icon: "chart.bar.fill", color: .purple)
                        }
                        
                        if let lastUpdated = stats.lastUpdated {
                            Text("Last Updated: \(formatDate(lastUpdated))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Database Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Location", value: dbInfo.location)
                        InfoRow(label: "Size", value: dbInfo.size)
                        InfoRow(label: "Cached Items", value: "\(dbInfo.itemCount)")
                    }
                    
                    Button {
                        NSWorkspace.shared.selectFile(dbInfo.location, inFileViewerRootedAtPath: "")
                    } label: {
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

struct DiagnosticsPanel: View {
    @ObservedObject var manager: MacStudioServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics & Tests")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                diagnosticsStatusBadge
            }
            
            Text("Run the automated Python test suites (feature coverage, server smoke test, performance benchmarks) from the macOS app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            #if os(macOS)
            HStack(spacing: 12) {
                Button {
                    Task { await manager.runDiagnosticsSuite() }
                } label: {
                    Label(manager.isRunningDiagnostics ? "Running…" : "Run Diagnostics", systemImage: "hammer.fill")
                }
                .disabled(manager.isRunningDiagnostics)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(manager.diagnosticsLog, forType: .string)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }
                .disabled(manager.diagnosticsLog.isEmpty)
                
                if manager.isRunningDiagnostics {
                    ProgressView()
                }
            }
            #else
            Text("Diagnostics can only run from the macOS control panel.")
                .font(.footnote)
                .foregroundColor(.secondary)
            #endif
            
            if let lastRun = manager.diagnosticsLastRun {
                Text("Last run: \(formatLastRun(lastRun))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let error = manager.diagnosticsErrorMessage {
                Text("⚠️ \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            ScrollView {
                Text(manager.diagnosticsLog.isEmpty ? "No diagnostics run yet." : manager.diagnosticsLog)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var diagnosticsStatusBadge: some View {
        let (label, color, icon) = statusDisplay()
        return Label(label, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
    
    private func statusDisplay() -> (String, Color, String) {
        if manager.isRunningDiagnostics {
            return ("Running…", .orange, "hourglass")
        }
        if let passed = manager.diagnosticsPassed {
            return passed ? ("All tests passed", .green, "checkmark.circle.fill")
                : ("Needs attention", .red, "exclamationmark.triangle.fill")
        }
        return ("Not run yet", .secondary, "questionmark.circle")
    }
    
    private func formatLastRun(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
