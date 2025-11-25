//
//  RepertoireComparisonTab.swift
//  MacStudioServerSimulator
//
//  Repertoire comparison UI for the Tests tab.
//

import SwiftUI
import AppKit

struct RepertoireComparisonTab: View {
    @ObservedObject var controller: RepertoireAnalysisController
    @ObservedObject var audioPlayer: RepertoireAudioPlayer
    @State private var isTargeted = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            Divider()
            content
        }
        .padding(12)
        .task {
            guard !controller.hasLoadedDefaults else { return }
            controller.hasLoadedDefaults = true
            await controller.loadDefaultSpotify()
            await controller.loadDefaultTruth()
            await controller.loadDefaultBpmReferences()
            await controller.loadDefaultFolder()
        }
        .alert("Repertoire Comparison", isPresented: Binding(
            get: { controller.alertMessage != nil },
            set: { if !$0 { controller.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { controller.alertMessage = nil }
        } message: {
            Text(controller.alertMessage ?? "")
        }
    }
    
    private func handleDropFromProviders(_ providers: [NSItemProvider]) -> Bool {
        let typeIdentifier = "public.file-url"
        var found = false
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                found = true
                group.enter()
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            urls.append(url)
                            group.leave()
                        }
                    } else {
                        DispatchQueue.main.async {
                            group.leave()
                        }
                    }
                }
            }
        }
        
        guard found else { return false }
        
        group.notify(queue: .main) {
            _ = controller.handleDrop(urls)
        }
        
        return true
    }
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repertoire Comparison")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Import preview clips, match to Spotify reference, and compare BPM/Key results.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !controller.rows.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(controller.summaryLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text("Overall winner:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(controller.overallWinnerLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(controller.overallWinnerColor.opacity(controller.overallWinnerLabel == "—" ? 0.15 : 0.2))
                            )
                            .foregroundColor(controller.overallWinnerColor)
                            .help(controller.overallWinnerDetail)
                    }
                    if let folder = controller.currentFolderPath {
                        Text(folder)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                controller.pickFolder()
            } label: {
                Label("Choose Preview Folder…", systemImage: "folder")
            }
            
            Button {
                Task { await controller.reloadSpotify() }
            } label: {
                Label("Reload Spotify CSV", systemImage: "arrow.clockwise")
            }
            
            Button {
                Task { await controller.reloadTruth() }
            } label: {
                Label("Reload Truth CSV", systemImage: "arrow.triangle.2.circlepath")
            }
            
            Spacer()
            
            Button {
                controller.copyDetectedBpmKeyToClipboard()
            } label: {
                Label("Copy Detected BPM / Key", systemImage: "doc.on.doc")
            }
            .disabled(!controller.rows.contains { $0.analysis != nil })
            
            Button {
                controller.exportMismatches()
            } label: {
                Label("Export Mismatches", systemImage: "square.and.arrow.down")
            }
            .disabled(controller.rows.isEmpty)
            
            Button {
                controller.exportResults()
            } label: {
                Label("Export All Results", systemImage: "tray.and.arrow.down")
            }
            .disabled(controller.rows.isEmpty)
            
            Button {
                controller.startAnalysisFromButton()
            } label: {
                Label("Analyze with Latest Algorithms", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.rows.isEmpty || controller.isAnalyzing)
        }
    }
    
    private var content: some View {
        Group {
            if controller.rows.isEmpty {
                VStack(spacing: 12) {
                    Text("Drop preview files or choose a folder to begin.")
                        .foregroundColor(.secondary)
                    Text("Default: Songwise 1 / preview_samples_repertoire_90 if available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(controller.rows) {
                    TableColumn("#") { row in
                        Text("\(row.index)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(30)
                    
                    TableColumn("File") { row in
                        Text(row.fileName)
                            .lineLimit(1)
                            .padding(.trailing, 22)
                            .overlay(alignment: .trailing) {
                                Button {
                                    audioPlayer.togglePlayback(for: row)
                                } label: {
                                    Image(systemName: audioPlayer.isPlaying(row) ? "pause.circle.fill" : "play.circle.fill")
                                        .foregroundColor(audioPlayer.isPlaying(row) ? .accentColor : .secondary)
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.plain)
                                .help(audioPlayer.isPlaying(row) ? "Pause preview" : "Play preview")
                            }
                    }
                    .width(min: 140)
                    
                    TableColumn("Artist / Title") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayArtist)
                                .lineLimit(1)
                            Text(row.displayTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 200)
                    
                    TableColumn("Spotify BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sp = row.spotify {
                                let bpmColor = row.spotifyBpmVsTruth.color
                                let keyColor = row.spotifyKeyVsTruth.color
                                Text(sp.bpmText)
                                    .foregroundColor(bpmColor)
                                Text(sp.key)
                                    .font(.caption)
                                    .foregroundColor(keyColor)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 110)
                    
                    TableColumn("Google BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sp = row.spotify,
                               sp.googleBpm != nil || (sp.googleKey != nil && !sp.googleKey!.isEmpty) || (sp.keyQuality != nil && !sp.keyQuality!.isEmpty) {
                                if let gbpmText = sp.googleBpmText {
                                    Text(gbpmText)
                                        .foregroundColor(row.googleBpmVsTruth.color)
                                }
                                if let gkey = sp.googleKey {
                                    Text(gkey)
                                        .font(.caption)
                                        .foregroundColor(row.googleKeyVsTruth.color)
                                }
                                if let quality = sp.keyQuality {
                                    Text(quality)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 120)
                    
                    TableColumn("SongBPM / Deezer") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if row.spotify?.songBpm != nil || row.deezerBpmValue != nil {
                                if row.spotify?.songBpm != nil {
                                    Text(row.songBpmText)
                                        .foregroundColor(row.songBpmVsTruth.color)
                                }
                                if row.deezerBpmValue != nil {
                                    Text(row.deezerBpmText)
                                        .font(.caption)
                                        .foregroundColor(row.deezerBpmVsTruth.color)
                                }
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 110)
                    
                    TableColumn("Truth BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.truthBpmText)
                                .font(.caption)
                                .foregroundColor(row.truthBpmText == "—" ? .secondary : .green)
                            Text(row.truthKeyText)
                                .font(.caption)
                                .foregroundColor(row.truthKeyText == "—" ? .secondary : .green)
                            if let confidence = row.truthConfidenceLabel {
                                Text(confidence)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(row.truthConfidenceColor.opacity(0.18))
                                    )
                                    .foregroundColor(row.truthConfidenceColor)
                            }
                        }
                    }
                    .width(min: 110)
                    
                    TableColumn("Detected BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.detectedBpmText)
                                .foregroundColor(row.bpmMatch.color)
                            Text(row.detectedKeyText)
                                .font(.caption)
                                .foregroundColor(row.keyMatch.color)
                        }
                    }
                    .width(min: 130)
                    
                    TableColumn("Winner / Status") { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("BPM")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(row.bpmWinnerLabel)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(row.bpmWinnerColor.opacity(row.bpmWinnerLabel == "—" ? 0.15 : 0.2))
                                    )
                                    .foregroundColor(row.bpmWinnerColor)
                            }
                            HStack(spacing: 6) {
                                Text("Key")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(row.keyWinnerLabel)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(row.keyWinnerColor.opacity(row.keyWinnerLabel == "—" ? 0.15 : 0.2))
                                    )
                                    .foregroundColor(row.keyWinnerColor)
                            }
                            Text(row.statusText)
                                .font(.caption2)
                                .foregroundColor(row.statusColor)
                        }
                    }
                    .width(min: 140)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: ["public.file-url"], isTargeted: $isTargeted, perform: handleDropFromProviders)
                .overlay {
                    if controller.isAnalyzing {
                        ProgressView("Analyzing…")
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.windowBackgroundColor))
                                    .shadow(radius: 4)
                            )
                    }
                }
            }
        }
    }
}
