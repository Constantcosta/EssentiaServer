//
//  DrumStockpileView.swift
//  MacStudioServerSimulator
//
//  Three-pane macOS workflow for prepping drum stems into the training stockpile.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVFoundation

struct DrumStockpileView: View {
    @StateObject private var store: DrumStockpileStore
    @StateObject private var preview: DrumPreviewEngine
    
    @State private var currentPreviewItemID: UUID?
    @State private var isDroppingGroup = false
    @State private var isDroppingMidi = false
    @State private var showMidiImporter = false
    @State private var midiTargetItem: StockpileItem?
    @State private var customClassName: String = ""
    @State private var showCustomClassSheet = false
    @State private var exportInFlight = false
    @State private var renamingGroupID: UUID?
    @State private var renameText: String = ""
    @State private var showDeleteConfirm = false
    @State private var autoGateInFlight = false
    @State private var autoGateStatus: String?
    @State private var sortOrder: [KeyPathComparator<StockpileItem>] = [
        .init(\.originalFilename, order: .forward)
    ]
    
    init(
        store: DrumStockpileStore? = nil,
        preview: DrumPreviewEngine? = nil
    ) {
        _store = StateObject(wrappedValue: store ?? DrumStockpileStore())
        _preview = StateObject(wrappedValue: preview ?? DrumPreviewEngine())
    }
    
    var body: some View {
        NavigationSplitView {
            groupSidebar
        } content: {
            stemTable
        } detail: {
            inspectorPane
        }
        .navigationTitle("Drum Stockpile")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    importAudio()
                } label: {
                    Label("Import Files", systemImage: "square.and.arrow.down")
                }
                
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(store.selectedItemIDs.isEmpty)
                .help("Delete selected stems")
                
                Button {
                    commitExport()
                } label: {
                    if exportInFlight || store.isExporting {
                        ProgressView()
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Commit to Stockpile", systemImage: "externaldrive.badge.plus")
                    }
                }
                .disabled(store.items.isEmpty || store.isExporting)
                .help("Convert to mono WAV, preserve silence, gate if active, and write dataset.json")
            }
        }
        .fileImporter(
            isPresented: $showMidiImporter,
            allowedContentTypes: [.midi],
            allowsMultipleSelection: false
        ) { result in
            guard let target = midiTargetItem else { return }
            if case let .success(urls) = result, let url = urls.first {
                let ids = store.selectedItemIDs.isEmpty ? Set([target.id]) : store.selectedItemIDs
                for id in ids {
                    if let targetItem = store.items.first(where: { $0.id == id }) {
                        var metadata = targetItem.metadata
                        metadata.midiRef = url
                        store.updateMetadata(for: id, metadata: metadata)
                    }
                }
            }
            midiTargetItem = nil
        }
        .onChange(of: store.selectedItemIDs) { _, ids in
            autoGateStatus = nil
            autoGateInFlight = false
            guard let first = ids.first,
                  let item = store.items.first(where: { $0.id == first }) else {
                currentPreviewItemID = nil
                preview.stop()
                return
            }
            
            // Avoid reloading the same file on every gate/playhead tweak; only load on actual selection change.
            if currentPreviewItemID == item.id {
                preview.updateGate(item.gateSettings)
                return
            }
            
            currentPreviewItemID = item.id
            Task { @MainActor in
                await Task.yield() // Defer to avoid publishing during view update
                await preview.load(url: item.originalURL, gate: item.gateSettings)
            }
        }
        .alert("Delete selected files?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.remove(items: store.selectedItemIDs)
            }
        } message: {
            Text("This removes the selected stems from the stockpile list. Original files are untouched.")
        }
        .onChange(of: store.selectedGroupID) { _, _ in
            store.selectedItemIDs.removeAll()
            preview.stop()
            currentPreviewItemID = nil
        }
    }
}

// MARK: - Sidebar

private extension DrumStockpileView {
    var groupSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedGroupID) {
                Section(header: Text("Ingest Batches (\(store.groups.count))")) {
                    ForEach(store.groups) { group in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if renamingGroupID == group.id {
                                    TextField("Group Name", text: $renameText, onCommit: {
                                        store.renameGroup(group.id, to: renameText)
                                        renamingGroupID = nil
                                    })
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                } else {
                                    Text(group.name)
                                        .font(.headline)
                                }
                                Text("\(store.groupedItems[group.id]?.count ?? 0) files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if group.reviewed {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .help("Reviewed")
                            }
                            Button {
                                renamingGroupID = group.id
                                renameText = group.name
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Rename group")
                        }
                        .tag(group.id)
                        .contextMenu {
                            Button(group.reviewed ? "Mark Unreviewed" : "Mark Reviewed") {
                                store.toggleReviewed(group.id)
                            }
                            Button("Rename…") {
                                renamingGroupID = group.id
                                renameText = group.name
                            }
                            Button("Delete Group", role: .destructive) {
                                store.deleteGroup(group.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: isDroppingGroup ? 2 : 0.5, dash: [6]))
                    .foregroundColor(isDroppingGroup ? .accentColor : .secondary)
                    .padding(8)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDroppingGroup) { providers in
                handleGroupDrop(providers: providers)
            }
            
            Divider()
            
            HStack {
                Button {
                    let _ = store.createGroup(named: "Batch \(Date().formatted(.dateTime.hour().minute()))")
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                Spacer()
                if let selected = store.selectedGroupID {
                    Button {
                        store.toggleReviewed(selected)
                    } label: {
                        Label("Toggle Reviewed", systemImage: "checkmark.seal")
                    }
                }
            }
            .padding()
        }
    }
    
    func handleGroupDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        Task { @MainActor in
                            store.createGroup(fromFolder: url)
                        }
                    } else {
                        Task { @MainActor in
                            store.ingest(urls: [url], assignGroup: store.selectedGroupID)
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Table

private extension DrumStockpileView {
    var stemTable: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Select All in Group") {
                    store.selectedItemIDs = Set(filteredItems.map(\.id))
                }
                .disabled(filteredItems.isEmpty)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 6)
            Table(sortedItems, selection: $store.selectedItemIDs, sortOrder: $sortOrder) {
                TableColumn("Filename", value: \.originalFilename)
                TableColumn("Class") { item in
                    classPill(item)
                }
                TableColumn("Channels") { item in
                    Text(item.channelCount.map(String.init) ?? "–")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                TableColumn("Status") { item in
                    statusBadge(for: item.status)
                }
            }
            .background(TableColumnWidthPersister(storageKey: "DrumStockpile.ColumnWidths"))
            .contextMenu {
                classificationMenu(targetIDs: store.selectedItemIDs)
                Button {
                    showInFinder(for: store.selectedItemIDs)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                Button(role: .destructive) {
                    store.remove(items: store.selectedItemIDs)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(6)
            }
        }
    }
    
    var filteredItems: [StockpileItem] {
        guard let groupID = store.selectedGroupID else { return store.items }
        return store.items.filter { $0.groupID == groupID }
    }
    
    var sortedItems: [StockpileItem] {
        filteredItems.sorted(using: sortOrder)
    }
    
    @ViewBuilder
    func classPill(_ item: StockpileItem) -> some View {
        Menu {
            classificationMenu(targetIDs: [item.id])
        } label: {
            Text(item.classification.displayName)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(item.classification.color.opacity(0.2))
                .foregroundColor(item.classification.color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    func showInFinder(for itemIDs: Set<UUID>) {
        let targets = store.items.filter { itemIDs.contains($0.id) }
        let urls = targets.map(\.originalURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    
    @ViewBuilder
    func statusBadge(for status: StockpileStatus) -> some View {
        switch status {
        case .pending:
            Label("Pending", systemImage: "clock")
                .foregroundColor(.secondary)
        case .prepped:
            Label("Prepped", systemImage: "checkmark.circle")
                .foregroundColor(.blue)
        case .exported:
            Label("Exported", systemImage: "externaldrive")
                .foregroundColor(.green)
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    func classificationMenu(targetIDs: Set<UUID>) -> some View {
        Button("Mark as Kick") { store.updateClassification(for: targetIDs, to: .kick) }
        Button("Mark as Snare") { store.updateClassification(for: targetIDs, to: .snare) }
        Button("Mark as Hi-Hat") { store.updateClassification(for: targetIDs, to: .hihat) }
        Button("Mark as Tambourine") { store.updateClassification(for: targetIDs, to: .tambourine) }
        Button("Mark as Claps") { store.updateClassification(for: targetIDs, to: .claps) }
        Button("Mark as Toms") { store.updateClassification(for: targetIDs, to: .toms) }
        
        let customNames = Array(Set(store.items.compactMap { item -> String? in
            if case let .custom(name) = item.classification { return name }
            return nil
        })).sorted()
        if !customNames.isEmpty {
            Divider()
            ForEach(customNames, id: \.self) { name in
                Button("Mark as \(name)") {
                    store.updateClassification(for: targetIDs, to: .custom(name))
                }
            }
        }
        Divider()
        Button("Add Custom Class…") { showCustomClassSheet = true }
            .keyboardShortcut("n", modifiers: [.command])
    }
}

// MARK: - Inspector

private extension DrumStockpileView {
    var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = store.selectedItems.first {
                header(for: item)
                Divider()
                waveformPanel(for: item)
                Divider()
                gatePanel(for: item)
                Divider()
                contextPanel(for: item)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.quarternote.3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a stem to edit")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .sheet(isPresented: $showCustomClassSheet) {
            customClassSheet
        }
    }
    
    @ViewBuilder
    func header(for item: StockpileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.originalFilename)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)
            
            HStack(spacing: 16) {
                Label("\(preview.duration, format: .number.precision(.fractionLength(2)))s", systemImage: "timer")
                    .foregroundColor(.secondary)
                Label(item.channelCount ?? 0 > 1 ? "Stereo" : "Mono", systemImage: "waveform")
                    .foregroundColor(.secondary)
                if let group = store.groups.first(where: { $0.id == item.groupID }) {
                    Label(group.name, systemImage: "folder")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                classPill(item)
                
                Picker("Group", selection: Binding(get: { item.groupID }, set: { store.updateGroup(for: [item.id], to: $0) })) {
                    ForEach(store.groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
        }
    }
    
    @ViewBuilder
    func waveformPanel(for item: StockpileItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Editor")
                .font(.headline)
            if let amps = preview.amplitudes {
                VStack(spacing: 12) {
                    WaveformView(
                        data: amps,
                        gatedOverlay: preview.gatedWaveform,
                        duration: preview.duration,
                        currentTime: Binding(
                            get: { preview.currentTime },
                            set: { newValue in
                                preview.seek(to: newValue)
                            }
                        ),
                        loopEnabled: preview.loopEnabled,
                        loopRange: Binding(
                            get: { preview.loopRange },
                            set: { newValue in
                                preview.setLoop(range: newValue)
                            }
                        )
                    )
                        .frame(height: 140)
                    
                    if let spec = preview.spectrogram {
                        SpectrogramView(data: spec)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .frame(height: 140)
                            VStack(spacing: 8) {
                                if preview.spectrogramLoading {
                                    ProgressView("Loading spectral view…")
                                } else {
                                    Button("Load spectral view") {
                                        preview.loadSpectrogramIfNeeded()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView("Loading preview…")
            }
            
            HStack(spacing: 12) {
                Button {
                    preview.togglePlayPause()
                } label: {
                    Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Slider(
                    value: Binding(
                        get: { preview.currentTime },
                        set: { preview.seek(to: $0) }
                    ),
                    in: 0...max(preview.duration, 0.001)
                )
                .help("Scrub through the stem")
                
                Toggle("Loop", isOn: Binding(get: { preview.loopEnabled }, set: { enabled in
                    preview.loopEnabled = enabled
                    if enabled {
                        let existing = preview.loopRange ?? 0...preview.duration
                        let clamped = max(0, min(existing.lowerBound, preview.duration - 0.01))
                        let upper = max(clamped + 0.01, min(existing.upperBound, preview.duration))
                        preview.setLoop(range: clamped...upper)
                    } else {
                        preview.setLoop(range: nil)
                    }
                }))
                    .toggleStyle(.switch)
                    .frame(width: 120)
            }
        }
    }
    
    @ViewBuilder
    func gatePanel(for item: StockpileItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gate")
                .font(.headline)
            
            let gate = item.gateSettings
            
            HStack(spacing: 10) {
                Button {
                    triggerAutoGate(for: item)
                } label: {
                    Label(autoGateInFlight ? "Auto-Gate Peaks…" : "Auto-Gate Peaks", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(autoGateInFlight)
                .help("Analyze the waveform for clear peaks and set the gate threshold to isolate them.")
                
                if autoGateInFlight {
                    ProgressView()
                        .controlSize(.small)
                } else if let status = autoGateStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Toggle("Listen (Bypass Gate)", isOn: Binding(get: { !gate.active }, set: { bypass in
                var updated = gate
                updated.active = !bypass
                store.updateGate(for: item.id, gate: updated)
                preview.updateGate(updated)
            }))
            
            HStack {
                knob(
                    title: "Threshold",
                    value: Binding(get: { gate.threshold }, set: { newValue in
                        var updated = gate
                        updated.threshold = newValue
                        store.updateGate(for: item.id, gate: updated)
                        preview.updateGate(updated)
                    }),
                    range: -60...0,
                    format: "%.0f dB"
                )
                knob(
                    title: "Attack",
                    value: Binding(get: { gate.attack }, set: { newValue in
                        var updated = gate
                        updated.attack = newValue
                        store.updateGate(for: item.id, gate: updated)
                        preview.updateGate(updated)
                    }),
                    range: 0.001...0.5,
                    format: "%.0f ms",
                    scale: 1000
                )
                knob(
                    title: "Release",
                    value: Binding(get: { gate.release }, set: { newValue in
                        var updated = gate
                        updated.release = newValue
                        store.updateGate(for: item.id, gate: updated)
                        preview.updateGate(updated)
                    }),
                    range: 0.02...1.5,
                    format: "%.0f ms",
                    scale: 1000
                )
            }
        }
    }
    
    func triggerAutoGate(for item: StockpileItem) {
        guard !autoGateInFlight else { return }
        autoGateInFlight = true
        autoGateStatus = "Analyzing peaks…"
        let gateSnapshot = item.gateSettings
        
        Task {
            let suggestion = await preview.autoGate(from: gateSnapshot)
            await MainActor.run {
                if let suggestion, store.items.contains(where: { $0.id == item.id }) {
                    store.updateGate(for: item.id, gate: suggestion)
                    preview.updateGate(suggestion)
                    autoGateStatus = String(format: "Auto threshold set to %.0f dB", suggestion.threshold)
                } else {
                    autoGateStatus = "No clear peaks detected"
                }
                autoGateInFlight = false
            }
        }
    }
    
    @ViewBuilder
    func contextPanel(for item: StockpileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context")
                .font(.headline)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BPM")
                    HStack {
                        TextField("Optional BPM", value: Binding(
                            get: { item.metadata.bpm },
                            set: { newValue in
                                if store.selectedItemIDs.count > 1 {
                                    store.updateMetadata(for: store.selectedItemIDs, bpm: newValue, key: nil)
                                } else {
                                    var metadata = item.metadata
                                    metadata.bpm = newValue
                                    store.updateMetadata(for: item.id, metadata: metadata)
                                }
                            }), format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        
                        if store.selectedItemIDs.count > 1 {
                            Button("Apply to \(store.selectedItemIDs.count)") {
                                store.updateMetadata(for: store.selectedItemIDs, bpm: item.metadata.bpm, key: nil)
                            }
                            .buttonStyle(.bordered)
                            .help("Apply BPM to all selected stems")
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key")
                    HStack {
                        TextField("Key", text: Binding(
                            get: { item.metadata.key ?? "" },
                            set: { newValue in
                                var metadata = item.metadata
                                metadata.key = newValue.isEmpty ? nil : newValue
                                store.updateMetadata(for: item.id, metadata: metadata)
                            })
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        
                        if store.selectedItemIDs.count > 1 {
                            Button("Apply to \(store.selectedItemIDs.count)") {
                                store.updateMetadata(for: store.selectedItemIDs, bpm: nil, key: item.metadata.key)
                            }
                            .buttonStyle(.bordered)
                            .help("Apply key to all selected stems")
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("MIDI Offset")
                    Slider(
                        value: Binding(
                            get: { item.metadata.midiOffset ?? 0 },
                            set: { newValue in
                                var metadata = item.metadata
                                metadata.midiOffset = newValue
                                store.updateMetadata(for: item.id, metadata: metadata)
                            }),
                        in: -2...2,
                        step: 0.01
                    )
                    Text("\(item.metadata.midiOffset ?? 0, specifier: "%.2f")s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            midiDrop(for: item)
            
            HStack {
                let targetIDs = store.selectedItemIDs.isEmpty ? Set([item.id]) : store.selectedItemIDs
                Button {
                    store.markStatus(.prepped, for: targetIDs)
                } label: {
                    if targetIDs.count > 1 {
                        Label("Save \(targetIDs.count) Processed Copies", systemImage: "arrow.down.circle")
                    } else {
                        if store.selectedItems.allSatisfy({ $0.status == .prepped }) {
                            Label("Processed", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Save Processed Copy", systemImage: "arrow.down.circle")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    @ViewBuilder
    func midiDrop(for item: StockpileItem) -> some View {
        let hasMidi = item.metadata.midiRef != nil
        let targetIDs = store.selectedItemIDs.isEmpty ? Set([item.id]) : store.selectedItemIDs
        VStack(alignment: .leading, spacing: 4) {
            Text("MIDI Reference")
                .font(.subheadline)
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: isDroppingMidi ? 2 : 1, dash: [6]))
                    .foregroundColor(isDroppingMidi ? .accentColor : .secondary)
                    .frame(height: 72)
                
                HStack {
                    Image(systemName: hasMidi ? "checkmark.circle" : "tray.and.arrow.down")
                    VStack(alignment: .leading) {
                        Text(hasMidi ? (item.metadata.midiRef?.lastPathComponent ?? "") : "Drop MIDI file here")
                        Text("Used for grid alignment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Browse…") {
                        midiTargetItem = item
                        showMidiImporter = true
                    }
                }
                .padding(.horizontal, 12)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDroppingMidi) { providers in
                var handled = false
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                            guard let data = data as? Data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                            guard url.pathExtension.lowercased() == "mid" || url.pathExtension.lowercased() == "midi" else { return }
                            Task { @MainActor in
                                for id in targetIDs {
                                    if let target = store.items.first(where: { $0.id == id }) {
                                        var metadata = target.metadata
                                        metadata.midiRef = url
                                        store.updateMetadata(for: id, metadata: metadata)
                                    }
                                }
                            }
                        }
                        handled = true
                    }
                }
                return handled
            }
        }
    }
    
    var customClassSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Custom Class")
                .font(.headline)
            TextField("e.g. Rim, Clap, Perc", text: $customClassName)
            HStack {
                Spacer()
                Button("Cancel") { showCustomClassSheet = false; customClassName = "" }
                Button("Add") {
                    let trimmed = customClassName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.updateClassification(for: store.selectedItemIDs, to: .custom(trimmed))
                    customClassName = ""
                    showCustomClassSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Controls

private extension DrumStockpileView {
    @ViewBuilder
    func knob(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        format: String,
        scale: Float = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue * scale))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    func importAudio() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.begin { response in
            guard response == .OK else { return }
            store.ingest(urls: panel.urls, assignGroup: store.selectedGroupID)
        }
    }
    
    func commitExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder for the stockpile (files will be copied/converted)."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            exportInFlight = true
            Task {
                await store.commit(to: url)
                exportInFlight = false
            }
        }
    }
}

// MARK: - Table Column Width Persistence (AppKit bridge)

private struct TableColumnWidthPersister: NSViewRepresentable {
    let storageKey: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(storageKey: storageKey)
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    final class Coordinator: NSObject {
        private let storageKey: String
        private weak var observedTable: NSTableView?
        private var observer: NSObjectProtocol?
        
        init(storageKey: String) {
            self.storageKey = storageKey
        }
        
        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        func attach(to hostView: NSView) {
            guard observedTable == nil else { return }
            guard let table = findTable(from: hostView) else { return }
            observedTable = table
            applySavedWidths(to: table)
            
            observer = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidResizeNotification,
                object: table,
                queue: .main
            ) { [weak self, weak table] _ in
                guard let table else { return }
                self?.persistWidths(of: table)
            }
        }
        
        private func applySavedWidths(to table: NSTableView) {
            let defaults = UserDefaults.standard
            guard let saved = defaults.array(forKey: storageKey) as? [CGFloat],
                  !saved.isEmpty else { return }
            let count = min(saved.count, table.tableColumns.count)
            guard count > 0 else { return }
            for idx in 0..<count {
                table.tableColumns[idx].width = saved[idx]
            }
        }
        
        private func persistWidths(of table: NSTableView) {
            let widths = table.tableColumns.map { $0.width }
            UserDefaults.standard.set(widths, forKey: storageKey)
        }
        
        private func findTable(from root: NSView) -> NSTableView? {
            var queue: [NSView] = [root]
            var seen = Set<ObjectIdentifier>()
            
            while !queue.isEmpty {
                let current = queue.removeFirst()
                let id = ObjectIdentifier(current)
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                
                if let table = current as? NSTableView {
                    return table
                }
                queue.append(contentsOf: current.subviews)
                if let superview = current.superview {
                    queue.append(superview)
                }
            }
            return nil
        }
    }
}

// MARK: - Visualizers

struct WaveformView: View {
    let data: [Float]
    let gatedOverlay: [Float]?
    let duration: TimeInterval
    @Binding var currentTime: TimeInterval
    let loopEnabled: Bool
    @Binding var loopRange: ClosedRange<TimeInterval>?
    @State private var isDraggingHandle = false
    @State private var handleDragBase: ClosedRange<TimeInterval>?
    
    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let samples = data
            ZStack(alignment: .leading) {
                Canvas { context, _ in
                    guard samples.count > 1 else { return }
                    let path = Path { path in
                        for (idx, sample) in samples.enumerated() {
                            let x = CGFloat(idx) / CGFloat(samples.count - 1) * width
                            let y = height / 2
                            let magnitude = CGFloat(sample.clamped(to: 0...1)) * (height / 2)
                            path.move(to: CGPoint(x: x, y: y - magnitude))
                            path.addLine(to: CGPoint(x: x, y: y + magnitude))
                        }
                    }
                    context.stroke(path, with: .color(.accentColor.opacity(0.7)), lineWidth: 1)
                    
                    if let overlay = gatedOverlay, overlay.count > 1 {
                        let overlayPath = Path { path in
                            for (idx, sample) in overlay.enumerated() {
                                let x = CGFloat(idx) / CGFloat(overlay.count - 1) * width
                                let y = height / 2
                                let magnitude = CGFloat(sample.clamped(to: 0...1)) * (height / 2)
                                path.move(to: CGPoint(x: x, y: y - magnitude))
                                path.addLine(to: CGPoint(x: x, y: y + magnitude))
                            }
                        }
                        context.stroke(overlayPath, with: .color(.green.opacity(0.9)), lineWidth: 1.2)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .offset(x: scrubX(in: width))
                
                if loopEnabled, let range = loopRange {
                    let startX = xPosition(for: range.lowerBound, width: width)
                    let endX = xPosition(for: range.upperBound, width: width)
                    let loopColor = Color.accentColor.opacity(0.2)
                    
                    Rectangle()
                        .fill(loopColor)
                        .frame(width: max(0, endX - startX), height: height)
                        .offset(x: startX)
                    
                    loopHandle(x: startX, height: height, isStart: true, width: width)
                    loopHandle(x: endX, height: height, isStart: false, width: width)
                }
            }
            .coordinateSpace(name: "waveform-area")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("waveform-area"))
                    .onChanged { value in
                        guard !isDraggingHandle else { return }
                        let t = time(at: value.location.x, width: width)
                        guard t.isFinite else { return }
                        currentTime = t
                    }
                    .onEnded { value in
                        guard !isDraggingHandle else { return }
                        let t = time(at: value.location.x, width: width)
                        guard t.isFinite else { return }
                        currentTime = t
                    }
            )
        }
    }
    
    private func scrubX(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let ratio = min(max(currentTime / duration, 0), 1)
        return CGFloat(ratio) * width
    }
    
    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let ratio = min(max(time / duration, 0), 1)
        return CGFloat(ratio) * width
    }
    
    private func loopHandle(x: CGFloat, height: CGFloat, isStart: Bool, width: CGFloat) -> some View {
        let hitWidth: CGFloat = 28
        let barWidth: CGFloat = 8
        
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: hitWidth, height: height)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor)
                .frame(width: barWidth, height: height)
                .shadow(color: .accentColor.opacity(0.35), radius: 2)
            Capsule()
                .fill(Color.white.opacity(0.65))
                .frame(width: 3, height: 26)
        }
        .frame(width: hitWidth, height: height)
        .offset(x: x - (hitWidth / 2))
        .contentShape(Rectangle())
        .highPriorityGesture(handleDrag(isStart: isStart, width: width))
        .accessibilityLabel(isStart ? "Loop start handle" : "Loop end handle")
        .accessibilityHint("Drag to adjust the loop \(isStart ? "start" : "end") point")
    }
    
    private func handleDrag(isStart: Bool, width: CGFloat) -> some Gesture {
        let minSpan: TimeInterval = 0.05
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("waveform-area"))
            .onChanged { value in
                guard duration > 0, width > 0 else { return }
                if !isDraggingHandle { isDraggingHandle = true }
                
                if handleDragBase == nil {
                    let current = loopRange ?? 0...duration
                    let lower = max(0, min(duration, current.lowerBound))
                    let upper = max(lower + minSpan, min(duration, current.upperBound))
                    handleDragBase = lower...upper
                }
                guard let base = handleDragBase else { return }
                
                let secondsPerPoint = duration / width
                let delta = TimeInterval(value.translation.width) * secondsPerPoint
                
                if isStart {
                    let maxStart = base.upperBound - minSpan
                    let newStart = min(max(0, base.lowerBound + delta), maxStart)
                    loopRange = newStart...base.upperBound
                } else {
                    let newEnd = max(base.lowerBound + minSpan, min(duration, base.upperBound + delta))
                    loopRange = base.lowerBound...newEnd
                }
            }
            .onEnded { _ in
                handleDragBase = nil
                isDraggingHandle = false
            }
    }
    
    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        let clampedX = min(max(0, x), width)
        let ratio = clampedX / width
        return ratio * duration
    }
}

struct SpectrogramView: View {
    let data: [[Float]]
    
    var body: some View {
        GeometryReader { proxy in
            let rows = data.count
            let cols = data.first?.count ?? 0
            Canvas { context, size in
                guard rows > 0, cols > 0 else { return }
                let cellWidth = size.width / CGFloat(cols)
                let cellHeight = size.height / CGFloat(rows)
                
                for row in 0..<rows {
                    for col in 0..<cols {
                        let value = data[row][col].clamped(to: 0...1)
                        let hue = 0.6 - 0.6 * Double(value)
                        let color = Color(hue: hue, saturation: 0.9, brightness: 0.9)
                        let rect = CGRect(x: CGFloat(col) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .background(
                LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}

// MARK: - Helpers

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
