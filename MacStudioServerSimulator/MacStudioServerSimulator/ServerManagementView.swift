//
//  ServerManagementView.swift
//  MacStudioServerSimulator
//
//  macOS control panel for the local audio-analysis server
//

import SwiftUI
import AppKit

private enum ManagementTab: Int {
    case tests = 0
    case logs = 1
    case stockpile = 2
}

struct ServerManagementView: View {
    @ObservedObject var manager: MacStudioServerManager
    @State private var selectedTab: ManagementTab = .stockpile
    @State private var selectedTestsMode: TestsTabMode = .repertoire
    @StateObject private var logStore = LogStore()
    @StateObject private var stockpileStore = DrumStockpileStore()
    @StateObject private var stockpilePreview = DrumPreviewEngine()
    @StateObject private var testRunner = ABCDTestRunner()
    @StateObject private var repertoireController: RepertoireAnalysisController
    @StateObject private var repertoireAudioPlayer = RepertoireAudioPlayer()
    
    init(manager: MacStudioServerManager) {
        self.manager = manager
        _repertoireController = StateObject(wrappedValue: RepertoireAnalysisController(manager: manager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ServerStatusHeader(manager: manager)
            
            Divider()
            
            Picker("View", selection: $selectedTab) {
                Label("Tests", systemImage: "checklist").tag(ManagementTab.tests)
                Label("Logs", systemImage: "doc.text.fill").tag(ManagementTab.logs)
                Label("Drum Stockpile", systemImage: "waveform.path").tag(ManagementTab.stockpile)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Group {
                switch selectedTab {
                case .tests:
                    TestsTab(
                        manager: manager,
                        testRunner: testRunner,
                        selectedMode: $selectedTestsMode,
                        repertoireController: repertoireController,
                        audioPlayer: repertoireAudioPlayer
                    )
                case .logs:
                    LogsTab(logStore: logStore)
                case .stockpile:
                    DrumStockpileView(store: stockpileStore, preview: stockpilePreview)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            // Skip server checks when landing on Stockpile; user can switch tabs to trigger status.
            guard selectedTab != .stockpile else { return }
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
