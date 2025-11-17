//
//  ServerManagementTestsTab.swift
//  MacStudioServerSimulator
//
//  ABCD Test Suite Tab
//

import SwiftUI

struct TestsTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @StateObject private var testRunner = ABCDTestRunner()
    
    var body: some View {
        HSplitView {
            // Left: Test Controls and Console
            VStack(spacing: 0) {
                // Test Runner Section
                ScrollView {
                    VStack(spacing: 16) {
                        Text("🧪 ABCD Test Suite")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        Text("Run comprehensive performance tests")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Test A
                        TestButton(
                            title: "Test A: 6 Preview Files",
                            subtitle: "Basic multithread test (~5-10s)",
                            testType: .testA,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        // Test B
                        TestButton(
                            title: "Test B: 6 Full Songs",
                            subtitle: "Full song processing (~30-60s)",
                            testType: .testB,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        // Test C
                        TestButton(
                            title: "Test C: 12 Preview Files",
                            subtitle: "Batch sequencing test (~10-20s)",
                            testType: .testC,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        // Test D
                        TestButton(
                            title: "Test D: 12 Full Songs",
                            subtitle: "Full stress test (~60-120s)",
                            testType: .testD,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Run All Button
                        Button {
                            Task { await testRunner.runAllTests() }
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Run All Tests")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(testRunner.isRunning)
                        
                        // Open CSV Folder Button
                        Button {
                            openCSVFolder()
                        } label: {
                            Label("Open CSV Folder", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
                .frame(height: 520) // Fixed height for test controls
                
                Divider()
                
                // Console Output - expands to fill remaining space
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Console Output")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Copy All") {
                            let allText = testRunner.outputLines.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(allText, forType: .string)
                            testRunner.addOutput("📋 Copied \(testRunner.outputLines.count) lines to clipboard")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear") {
                            testRunner.clearOutput()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding([.horizontal, .top], 12)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(testRunner.outputLines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .onChange(of: testRunner.outputLines.count) { _, _ in
                            if let lastIndex = testRunner.outputLines.indices.last {
                                withAnimation {
                                    proxy.scrollTo(lastIndex, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity) // Expands to fill available space
            }
            .frame(minWidth: 350, maxWidth: 400)
            
            // Right: Results Dashboard
            ABCDResultsDashboard(testRunner: testRunner)
        }
    }
    
    private func openCSVFolder() {
        // Use the same project path logic as the test runner
        var projectPath = ""
        
        // Try to find the EssentiaServer directory
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            // From app bundle, go up to find EssentiaServer
            var searchPath = bundlePath as String
            
            // Keep going up directories until we find run_test.sh or hit root
            for _ in 0..<10 {
                let testScriptPath = (searchPath as NSString).appendingPathComponent("run_test.sh")
                if FileManager.default.fileExists(atPath: testScriptPath) {
                    projectPath = searchPath
                    break
                }
                searchPath = (searchPath as NSString).deletingLastPathComponent
            }
            
            // If we didn't find it, try hardcoded path
            if projectPath.isEmpty || projectPath == "/" {
                let documentsPath = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
                if FileManager.default.fileExists(atPath: documentsPath + "/run_test.sh") {
                    projectPath = documentsPath
                }
            }
        } else {
            // Fallback to hardcoded path
            projectPath = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
        }
        
        let csvPath = (projectPath as NSString).appendingPathComponent("csv")
        
        if FileManager.default.fileExists(atPath: csvPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: csvPath))
            testRunner.addOutput("📂 Opened CSV folder: \(csvPath)")
        } else {
            testRunner.addOutput("⚠️ CSV folder not found at: \(csvPath)")
            testRunner.addOutput("Project path: \(projectPath)")
        }
    }
}

// MARK: - Test Button

struct TestButton: View {
    let title: String
    let subtitle: String
    let testType: ABCDTestType
    @ObservedObject var runner: ABCDTestRunner
    let serverRunning: Bool  // Not used anymore but kept for compatibility
    
    private var isRunning: Bool {
        runner.currentTest == testType
    }
    
    private var result: ABCDTestResult? {
        runner.results[testType]
    }
    
    var body: some View {
        Button {
            Task { await runner.runTest(testType) }
        } label: {
            HStack(spacing: 12) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 40, height: 40)
                    
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let result = result {
                        HStack(spacing: 6) {
                            Text("\(String(format: "%.2f", result.duration))s")
                                .font(.caption2)
                            Text("•")
                            Text("\(result.successCount)/\(result.totalCount)")
                                .font(.caption2)
                                .foregroundColor(result.passed ? .green : .red)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
    }
    
    private var statusColor: Color {
        if isRunning {
            return .blue
        } else if let result = result {
            return result.passed ? .green : .red
        } else {
            return .gray
        }
    }
    
    private var statusIcon: String {
        if let result = result {
            return result.passed ? "checkmark" : "xmark"
        } else {
            return "play.fill"
        }
    }
    
    private var borderColor: Color {
        if isRunning {
            return .blue
        } else if let result = result {
            return result.passed ? .green.opacity(0.5) : .red.opacity(0.5)
        } else {
            return .clear
        }
    }
}

#Preview {
    TestsTab(manager: MacStudioServerManager())
}
