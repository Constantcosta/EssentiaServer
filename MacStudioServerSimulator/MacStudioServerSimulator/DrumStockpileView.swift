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
    @StateObject var store: DrumStockpileStore
    @StateObject var preview: DrumPreviewEngine
    
    @State var currentPreviewItemID: UUID?
    @State var isDroppingGroup = false
    @State var isDroppingFiles = false
    @State var isDroppingMidi = false
    @State var showMidiImporter = false
    @State var midiTargetItem: StockpileItem?
    @State var customClassName: String = ""
    @State var showCustomClassSheet = false
    @State var exportInFlight = false
    @State var renamingGroupID: UUID?
    @State var renameText: String = ""
    @State var showDeleteConfirm = false
    @State var autoGateInFlight = false
    @State var autoGateStatus: String?
    @State var activePluginUI: AudioInsertSlot?
    @State var sortOrder: [KeyPathComparator<StockpileItem>] = [
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
        .background(SplitViewAutosaveAttacher(storageKey: "DrumStockpile.SplitView"))
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
            loadPreview(for: ids)
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
    
    private func loadPreview(for ids: Set<UUID>) {
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
            await preview.load(url: item.originalURL, gate: item.gateSettings, classification: item.classification)
        }
    }
}
