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
    @State private var searchQuery = ""
    @State private var showingClearAlert = false
    @StateObject private var logStore = LogStore()
    @AppStorage("autoManageLocalServer") private var autoManageLocalServer = true
    
    var body: some View {
        VStack(spacing: 0) {
            ServerStatusHeader(manager: manager)
            
            Divider()
            
            Picker("View", selection: $selectedTab) {
                Label("Overview", systemImage: "chart.bar.fill").tag(0)
                Label("Cache", systemImage: "tray.full.fill").tag(1)
                Label("Calibration", systemImage: "target").tag(2)
                Label("Tests", systemImage: "checklist").tag(3)
                Label("Logs", systemImage: "doc.text.fill").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Show all tabs but only make the selected one visible
            // This preserves scroll positions without TabView complexity
            // Using .equatable() and lazy loading for performance
            ZStack {
                if selectedTab == 0 {
                    OverviewTab(manager: manager)
                        .id("overview")
                        .transition(.opacity)
                }
                
                if selectedTab == 1 {
                    CacheTab(manager: manager, searchQuery: $searchQuery, showingClearAlert: $showingClearAlert)
                        .id("cache")
                        .transition(.opacity)
                }
                
                if selectedTab == 2 {
                    CalibrationTab(manager: manager)
                        .id("calibration")
                        .transition(.opacity)
                }
                
                if selectedTab == 3 {
                    TestsTab(manager: manager)
                        .id("tests")
                        .transition(.opacity)
                }
                
                if selectedTab == 4 {
                    LogsTab(logStore: logStore)
                        .id("logs")
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await manager.autoStartServerIfNeeded(autoManageEnabled: autoManageLocalServer)
            if manager.isServerRunning {
                await manager.fetchServerStats()
            }
        }
        .onChange(of: autoManageLocalServer) { _, enabled in
            if enabled {
                Task {
                    await manager.autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)
                }
            } else {
                manager.recordAutoManageDisabled()
            }
        }
    }
}

// MARK: - Server Status Header

struct ServerStatusHeader: View {
    @ObservedObject var manager: MacStudioServerManager
    @AppStorage("autoManageLocalServer") private var autoManageLocalServer = true
    @State private var showingAutoManageInfo = false
    
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

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $autoManageLocalServer) {
                    Text("Auto-manage server")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .help("Automatically launch the bundled Python analyzer as soon as the Mac app opens.")
                
                Button {
                    showingAutoManageInfo = true
                } label: {
                    Label("How auto-manage works", systemImage: "info.circle")
                        .font(.caption2)
                }
                .buttonStyle(.link)
                
                if let banner = manager.autoManageBanner {
                    AutoManageStatusView(banner: banner)
                }
            }
            .frame(maxWidth: 240, alignment: .leading)
            
            HStack(spacing: 8) {
                if manager.isServerRunning {
                    Button {
                        Task { await manager.fetchServerStats() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(manager.isLoading)
                    
                    Button {
                        Task { await manager.restartServer() }
                    } label: {
                        Label("Restart", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(manager.isLoading)
                    
                    Button {
                        Task { await manager.stopServer() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                    .disabled(manager.isLoading)
                } else {
                    Button {
                        Task { await manager.startServer() }
                    } label: {
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
        .sheet(isPresented: $showingAutoManageInfo) {
            AutoManageInfoSheet(
                manager: manager,
                isEnabled: $autoManageLocalServer
            )
        }
    }
}
