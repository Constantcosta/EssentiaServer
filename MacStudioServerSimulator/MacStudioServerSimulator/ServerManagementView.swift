//
//  ServerManagementView.swift
//  MacStudioServerSimulator
//
//  macOS control panel for the local audio-analysis server
//

import SwiftUI
import AppKit

struct ServerManagementView: View {
    @EnvironmentObject var manager: MacStudioServerManager
    @State private var selectedTab = 0
    @StateObject private var logStore = LogStore()
    
    var body: some View {
        VStack(spacing: 0) {
            ServerStatusHeader(manager: manager)
            
            Divider()
            
            Picker("View", selection: $selectedTab) {
                Label("Tests", systemImage: "checklist").tag(0)
                Label("Logs", systemImage: "doc.text.fill").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Keep both tabs alive and only toggle visibility.
            // This preserves in-progress work (e.g. Repertoire analysis)
            // and scroll positions while you switch between Tests and Logs.
            ZStack {
                TestsTab(manager: manager)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                    .id("tests")
                
                LogsTab(logStore: logStore)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                    .id("logs")
            }
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
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
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isServerRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isServerRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                    Text("Port \(manager.serverPort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
            
            HStack(spacing: 8) {
                Button {
                    Task {
                        await manager.checkServerStatus()
                        if manager.isServerRunning {
                            await manager.fetchServerStats(silently: true)
                        }
                    }
                } label: {
                    Label("Check Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoading)
                
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
