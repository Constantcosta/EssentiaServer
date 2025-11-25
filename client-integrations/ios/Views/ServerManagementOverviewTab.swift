//
//  ServerManagementOverviewTab.swift
//

#if os(macOS)

import SwiftUI
import AppKit

struct OverviewTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @State private var dbInfo: (size: String, location: String, itemCount: Int) = ("", "", 0)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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

#endif

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
        .background(.thinMaterial)
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
