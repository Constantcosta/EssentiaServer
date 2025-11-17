//
//  ServerManagementLogsTab.swift
//  MacStudioServerSimulator
//

import SwiftUI
import AppKit

struct LogsTab: View {
    @ObservedObject var logStore: LogStore
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Toggle(isOn: $logStore.autoRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: logStore.autoRefresh ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                            .foregroundColor(logStore.autoRefresh ? .green : .secondary)
                        Text("Live Updates")
                    }
                }
                .toggleStyle(.button)
                
                if let lastUpdate = logStore.lastUpdate {
                    Text("Updated: \(lastUpdate, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if logStore.logFileSize > 0 {
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: logStore.logFileSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle(isOn: $autoScroll) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                }
                .toggleStyle(.button)
                .help("Auto-scroll to bottom")
                
                Button {
                    logStore.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear log file")
                
                Button {
                    logStore.loadLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh now")
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logStore.logContent, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy logs to clipboard")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Log viewer
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logStore.logContent)
                        .font(.system(.caption, design: .monospaced))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("logBottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: logStore.logContent) {
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .task {
            logStore.loadLogs()
            // Auto-enable live updates when tab appears
            logStore.autoRefresh = true
        }
        .onDisappear {
            // Disable auto-refresh when leaving tab to save resources
            logStore.autoRefresh = false
        }
    }
}
