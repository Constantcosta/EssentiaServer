//
//  ServerManagementTestsTab.swift
//  MacStudioServerSimulator
//
//  Tests tab: ABCD test suite + Repertoire comparison view.
//

import SwiftUI
import AppKit

struct TestsTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @ObservedObject var testRunner: ABCDTestRunner
    @Binding var selectedMode: TestsTabMode
    @ObservedObject var repertoireController: RepertoireAnalysisController
    @ObservedObject var audioPlayer: RepertoireAudioPlayer
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedMode) {
                Label("ABCD Tests", systemImage: "checklist").tag(TestsTabMode.abcd)
                Label("Repertoire", systemImage: "music.note.list").tag(TestsTabMode.repertoire)
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal])
            
            Divider()
            
            if selectedMode == .abcd {
                abcdBody
            } else {
                RepertoireComparisonTab(controller: repertoireController, audioPlayer: audioPlayer)
            }
        }
    }
    
    private var abcdBody: some View {
        HSplitView {
            VStack(spacing: 0) {
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
                        
                        TestButton(
                            title: "Test A: 6 Preview Files",
                            subtitle: "Basic multithread test (~5-10s)",
                            testType: .testA,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        TestButton(
                            title: "Test B: 6 Full Songs",
                            subtitle: "Full song processing (~30-60s)",
                            testType: .testB,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        TestButton(
                            title: "Test C: 12 Preview Files",
                            subtitle: "Batch sequencing test (~10-20s)",
                            testType: .testC,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        TestButton(
                            title: "Test D: 12 Full Songs",
                            subtitle: "Full stress test (~60-120s)",
                            testType: .testD,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
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
                .frame(height: 520)
                
                Divider()
                
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
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 350, maxWidth: 400)
            
            ABCDResultsDashboard(testRunner: testRunner)
        }
    }
    
    private func openCSVFolder() {
        var projectPath = ""
        
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            var searchPath = bundlePath as String
            
            for _ in 0..<10 {
                let testScriptPath = (searchPath as NSString).appendingPathComponent("run_test.sh")
                if FileManager.default.fileExists(atPath: testScriptPath) {
                    projectPath = searchPath
                    break
                }
                searchPath = (searchPath as NSString).deletingLastPathComponent
            }
            
            if projectPath.isEmpty || projectPath == "/" {
                let documentsPath = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
                if FileManager.default.fileExists(atPath: documentsPath + "/run_test.sh") {
                    projectPath = documentsPath
                }
            }
        } else {
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

enum TestsTabMode: Hashable {
    case abcd
    case repertoire
}

struct TestButton: View {
    let title: String
    let subtitle: String
    let testType: ABCDTestType
    @ObservedObject var runner: ABCDTestRunner
    let serverRunning: Bool
    
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
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let result = result {
                        HStack(spacing: 6) {
                            Text(String(format: "%.2f", result.duration) + "s")
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
    let manager = MacStudioServerManager()
    return TestsTab(
        manager: manager,
        testRunner: ABCDTestRunner(),
        selectedMode: .constant(.repertoire),
        repertoireController: RepertoireAnalysisController(manager: manager),
        audioPlayer: RepertoireAudioPlayer()
    )
}
