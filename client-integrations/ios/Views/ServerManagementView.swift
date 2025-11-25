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
#endif
