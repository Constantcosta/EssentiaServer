//
//  ServerManagementAutoManage.swift
//  MacStudioServerSimulator
//

import SwiftUI

typealias AutoManageBanner = MacStudioServerManager.AutoManageBanner

struct AutoManageInfoSheet: View {
    @ObservedObject var manager: MacStudioServerManager
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Keep the analyzer in sync with this Mac app.")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("When auto-manage is enabled, the app launches the bundled Python analyzer as soon as the UI loads, watches for failures, and lets you take back control at any time.")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Starts the analyzer automatically at launch", systemImage: "play.circle.fill")
                        Label("Shows a status banner whenever it starts, skips, or hits an error", systemImage: "eye")
                        Label("Respects manual stops so the server stays off until you say otherwise", systemImage: "hand.raised.fill")
                    }
                    .font(.caption)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(10)
                    
                    Toggle("Start the analyzer automatically", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .font(.headline)
                    
                    if let banner = manager.autoManageBanner {
                        AutoManageStatusView(banner: banner)
                    }
                    
                    Text("Prefer to launch it yourself? Turn auto-manage off and use the Start/Stop controls in the main toolbar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Auto-manage Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
    }
}

struct AutoManageStatusView: View {
    let banner: AutoManageBanner
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.symbolName)
                .font(.title3)
                .foregroundColor(banner.tintColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.displayTitle)
                    .font(.headline)
                Text(banner.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(banner.tintColor.opacity(0.08))
        )
    }
}

private extension MacStudioServerManager.AutoManageBanner {
    var displayTitle: String { kind.titleText }
    var symbolName: String { kind.symbolName }
    var tintColor: Color { kind.tint }
}

private extension MacStudioServerManager.AutoManageBanner.Kind {
    var titleText: String {
        switch self {
        case .info:
            return "Auto-manage update"
        case .success:
            return "Auto-manage running"
        case .warning:
            return "Auto-manage paused"
        case .error:
            return "Auto-manage issue"
        }
    }
    
    var symbolName: String {
        switch self {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
    
    var tint: Color {
        switch self {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
