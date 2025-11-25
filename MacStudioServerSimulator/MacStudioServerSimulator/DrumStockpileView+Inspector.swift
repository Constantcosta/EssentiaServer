//
//  DrumStockpileView+Inspector.swift
//  MacStudioServerSimulator
//
//  Inspector and detail controls for stockpile stems.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVFoundation
import AudioToolbox
#if canImport(AudioUnit)
import AudioUnit
#endif

extension DrumStockpileView {
    var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = store.selectedItems.first {
                header(for: item)
                Divider()
                waveformPanel(for: item)
                Divider()
                gatePanel(for: item)
                Divider()
                pluginsPanel(for: item)
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
        .sheet(item: $activePluginUI) { slot in
            PluginUIWrapper(slot: slot)
        }
        .sheet(isPresented: $showCustomClassSheet) {
            customClassSheet
        }
    }
    
    @ViewBuilder
    private func header(for item: StockpileItem) -> some View {
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
    private func waveformPanel(for item: StockpileItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Editor")
                .font(.headline)
            let gate = item.gateSettings
            let floorLevel: Float? = {
                guard gate.active, let floorDb = gate.floorDb, let peak = preview.waveformPeak, peak > 0 else { return nil }
                let floorLinear = pow(10.0, floorDb / 20.0)
                let ratio = floorLinear / peak
                return Float(ratio)
            }()
            if let error = preview.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                    Text("The source file is missing or unreadable. Please relink or reimport the stem.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            } else if let amps = preview.amplitudes {
                VStack(spacing: 12) {
                    WaveformView(
                        data: amps,
                        gatedOverlay: preview.gatedWaveform,
                        duration: preview.duration,
                        floorLevel: floorLevel,
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
            
            HStack(spacing: 12) {
                Label("Playhead", systemImage: "clock")
                    .foregroundColor(.secondary)
                Text(timecode(preview.currentTime))
                    .font(.system(.body, design: .monospaced))
                Text(" / ")
                    .foregroundColor(.secondary)
                Text(timecode(preview.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                if preview.isPlaying {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }
            .font(.subheadline)
            .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private func gatePanel(for item: StockpileItem) -> some View {
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
                } else if gate.autoApplied {
                    Label("Auto applied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
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
                        updated.autoApplied = false
                        updated.active = true
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
                        updated.autoApplied = false
                        updated.active = true
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
                        updated.autoApplied = false
                        updated.active = true
                        store.updateGate(for: item.id, gate: updated)
                        preview.updateGate(updated)
                    }),
                    range: 0.02...1.5,
                    format: "%.0f ms",
                    scale: 1000
                )
                knob(
                    title: "Floor (dB)",
                    value: Binding(
                        get: { gate.floorDb ?? -60 },
                        set: { newValue in
                            var updated = gate
                            updated.floorDb = newValue
                            updated.autoApplied = false
                            updated.active = true
                            store.updateGate(for: item.id, gate: updated)
                            preview.updateGate(updated)
                        }
                    ),
                    range: -90.0 ... -10.0,
                    format: "%.0f dB"
                )
            }
        }
    }
    
    @ViewBuilder
    private func pluginsPanel(for _: StockpileItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plugins")
                .font(.headline)
            Text("Gate runs first, then the inserts below.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let error = preview.pluginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if preview.pluginSlots.isEmpty {
                Text("No inserts in the signal path yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(preview.pluginSlots) { slot in
                        PluginRow(
                            slot: slot,
                            isFirst: preview.pluginSlots.first?.id == slot.id,
                            isLast: preview.pluginSlots.last?.id == slot.id,
                            onOpenUI: { activePluginUI = slot },
                            onMoveUp: { preview.movePlugin(slot, direction: -1) },
                            onMoveDown: { preview.movePlugin(slot, direction: 1) },
                            onRemove: {
                                if activePluginUI?.id == slot.id {
                                    activePluginUI = nil
                                }
                                preview.removePlugin(slot)
                            }
                        )
                    }
                }
            }
            
            Menu {
                Button("Refresh plug-in list") {
                    preview.reloadAvailablePlugins()
                }
                if !preview.availablePlugins.isEmpty {
                    Divider()
                }
                ForEach(preview.availablePlugins) { plugin in
                    Button("\(plugin.name) – \(plugin.manufacturer)") {
                        preview.addPlugin(plugin)
                    }
                }
            } label: {
                Label("Add Plugin", systemImage: "plus.circle")
            }
            .disabled(preview.availablePlugins.isEmpty)
        }
    }
    
    private func triggerAutoGate(for item: StockpileItem) {
        guard !autoGateInFlight else { return }
        autoGateInFlight = true
        autoGateStatus = "Analyzing peaks…"
        let gateSnapshot = item.gateSettings
        
        Task {
            let suggestion = await preview.autoGate(from: gateSnapshot, classification: item.classification)
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
    private func contextPanel(for item: StockpileItem) -> some View {
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
                    Text(String(format: "%.2f", item.metadata.midiOffset ?? 0) + "s")
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
    private func midiDrop(for item: StockpileItem) -> some View {
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
    
    private var customClassSheet: some View {
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
    
    @ViewBuilder
    private func knob(
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
    
    private func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalSeconds = max(0, Int(seconds.rounded()))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
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

// MARK: - Plugin Hosting Helpers

private struct PluginRow: View {
    @ObservedObject var slot: AudioInsertSlot
    let isFirst: Bool
    let isLast: Bool
    let onOpenUI: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { !slot.isBypassed },
                set: { slot.isBypassed = !$0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.descriptor.name)
                        .fontWeight(.semibold)
                    Text(slot.descriptor.manufacturer)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            
            Spacer()
            
            Button {
                onOpenUI()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Open plug-in UI")
            
            Button {
                onMoveUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(isFirst)
            .help("Move plug-in earlier in the chain")
            
            Button {
                onMoveDown()
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(isLast)
            .help("Move plug-in later in the chain")
            
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove plug-in from chain")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

private struct PluginUIWrapper: View {
    @ObservedObject var slot: AudioInsertSlot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(slot.descriptor.name)
                .font(.headline)
            Text(slot.descriptor.manufacturer)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Divider()
            AudioUnitViewHost(audioUnit: slot.node.auAudioUnit)
                .frame(minWidth: 520, minHeight: 320)
        }
        .padding()
    }
}

private struct AudioUnitViewHost: NSViewRepresentable {
    let audioUnit: AUAudioUnit
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attachView(to: container, coordinator: context.coordinator)
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private func attachView(to container: NSView, coordinator: Coordinator) {
        audioUnit.requestViewController { viewController in
            DispatchQueue.main.async {
                if let viewController {
                    coordinator.embed(viewController: viewController, into: container)
                } else if let generic = makeGenericView() {
                    let controller = NSViewController()
                    controller.view = generic
                    coordinator.embed(viewController: controller, into: container)
                } else {
                    let placeholder = NSViewController()
                    let label = NSTextField(labelWithString: "No plug-in UI provided.")
                    label.alignment = .center
                    placeholder.view = label
                    coordinator.embed(viewController: placeholder, into: container)
                }
            }
        }
    }
    
    private func makeGenericView() -> NSView? {
        #if canImport(AudioUnit)
        return AUGenericView(audioUnit: audioUnit)
        #else
        return nil
        #endif
    }
    
    final class Coordinator {
        private var hostedController: NSViewController?
        
        func embed(viewController: NSViewController, into container: NSView) {
            hostedController?.view.removeFromSuperview()
            hostedController = viewController
            let childView = viewController.view
            childView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(childView)
            NSLayoutConstraint.activate([
                childView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                childView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                childView.topAnchor.constraint(equalTo: container.topAnchor),
                childView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
    }
}
