//
//  ServerManagementLogsTab.swift
//

#if os(macOS)

import SwiftUI
import AppKit

struct LogsTab: View {
    @State private var logContent = "Loading logs..."
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .onChange(of: autoRefresh) { _, enabled in
                        enabled ? startAutoRefresh() : stopAutoRefresh()
                    }
                
                Spacer()
                
                Button { loadLogs() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logContent, forType: .string)
                } label: {
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
        .task { loadLogs() }
        .onDisappear { stopAutoRefresh() }
    }
    
    private func loadLogs() {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/AudioAnalysisCache/server.log")
        if let content = try? String(contentsOf: logPath) {
            logContent = content.components(separatedBy: .newlines).suffix(200).joined(separator: "\n")
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

#endif
