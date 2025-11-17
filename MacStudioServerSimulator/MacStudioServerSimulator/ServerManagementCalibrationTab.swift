//
//  ServerManagementCalibrationTab.swift
//  MacStudioServerSimulator
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CalibrationTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @State private var showingImporter = false
    @AppStorage("calibrationFeatureSetVersion") private var featureSetVersion = "v1"
    @AppStorage("calibrationNotes") private var calibrationNotes = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introSection
                songsSection
                runSection
                logSection
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task { await manager.importCalibrationSongs(from: urls) }
            case .failure(let error):
                manager.calibrationError = error.localizedDescription
            }
        }
    }
    
    private var introSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calibration Toolkit")
                .font(.title3)
                .fontWeight(.bold)
            Text("Keep a fixed playlist of ten sanity-check tracks. The Mac app copies them into its sandbox, re-analyzes them after each code change, and runs the calibration builder against Spotify targets.")
                .font(.body)
                .foregroundColor(.secondary)
            Text("Songs live in \(manager.calibrationSongsFolderPath)")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
    
    private var songsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(manager.calibrationSongs.count)/\(manager.calibrationSongLimit) songs staged")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Add Songs…", systemImage: "plus.circle")
                    }
                    .disabled(manager.calibrationSongs.count >= manager.calibrationSongLimit)
                    
#if os(macOS)
                    Button {
                        manager.promptCalibrationFolderImport()
                    } label: {
                        Label("Import Folder…", systemImage: "folder.badge.plus")
                    }
                    .disabled(manager.calibrationSongs.count >= manager.calibrationSongLimit)
#endif
                    
                    Button(role: .destructive) {
                        manager.removeAllCalibrationSongs()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(manager.calibrationSongs.isEmpty)
                    
                    Menu {
                        Button("Reset Songs (keep exports)") {
                            Task { await manager.resetCalibrationWorkspace(includeExports: false) }
                        }
                        Button("Reset Songs + Exports") {
                            Task { await manager.resetCalibrationWorkspace(includeExports: true) }
                        }
                    } label: {
                        Label(
                            manager.isResettingCalibration ? "Resetting…" : "Reset Workspace…",
                            systemImage: manager.isResettingCalibration ? "hourglass" : "arrow.counterclockwise"
                        )
                    }
                    .disabled(manager.isResettingCalibration || manager.isCalibrationRunning)
                }
                
                if manager.calibrationSongs.isEmpty {
                    Text("Drag audio files into the Overview drop-zone, use “Add Songs…”, or import an entire folder to pin your calibration deck. Files are copied locally so you only need to do this once.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(manager.calibrationSongs) { song in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.headline)
                                    Text(song.artist)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(song.originalFilename)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(manager.calibrationTimestampFormatter.string(from: song.addedAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button(role: .destructive) {
                                        manager.removeCalibrationSong(song)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var runSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run Calibration")
                    .font(.headline)
                
                Picker("Feature Set", selection: $featureSetVersion) {
                    Text("Essentia v1").tag("v1")
                    Text("Hybrid v2").tag("v2")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                
                TextField("Notes for this run...", text: $calibrationNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                
                HStack {
                    Button {
                        Task { await manager.runCalibration(featureSetVersion: featureSetVersion, notes: calibrationNotes) }
                    } label: {
                        Label(manager.isCalibrationRunning ? "Running…" : "Run Calibration", systemImage: "target")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.calibrationSongs.isEmpty || manager.isCalibrationRunning)
                    
                    Button {
                        manager.openCalibrationExportsFolder()
                    } label: {
                        Label("Open Exports Folder", systemImage: "folder")
                    }
                }
                
                if manager.isCalibrationRunning {
                    ProgressView(value: manager.calibrationProgress)
                        .progressViewStyle(.linear)
                    Text("Processing \(Int(manager.calibrationProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let exportURL = manager.lastCalibrationExportURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last analyzer export (CSV)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Text(exportURL.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([exportURL])
                            } label: {
                                Label("Reveal", systemImage: "eye")
                            }
                        }
                    }
                }
                
                if let outputURL = manager.lastCalibrationOutputURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last calibration dataset (Parquet)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Text(outputURL.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                            } label: {
                                Label("Reveal", systemImage: "eye")
                            }
                            Button {
                                Task { await manager.compareLatestCalibrationDataset() }
                            } label: {
                                Label(
                                    manager.isComparingCalibration ? "Comparing…" : "Compare vs Spotify",
                                    systemImage: "chart.bar.doc.horizontal"
                                )
                            }
                            .disabled(manager.isComparingCalibration)
                        }
                        
                        if let comparison = manager.lastCalibrationComparison {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last comparison output")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ScrollView {
                                    Text(comparison)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 120)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                if let comparisonURL = manager.lastCalibrationComparisonURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last comparison report (CSV)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Text(comparisonURL.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([comparisonURL])
                            } label: {
                                Label("Reveal", systemImage: "doc.text")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var logSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calibration Log")
                    .font(.headline)
                
                if manager.calibrationLog.isEmpty {
                    Text("Logs will appear here as soon as you run the calibration tool.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(manager.calibrationLog, id: \.self) { entry in
                                Text(entry)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 8)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            .padding()
        }
    }
}
