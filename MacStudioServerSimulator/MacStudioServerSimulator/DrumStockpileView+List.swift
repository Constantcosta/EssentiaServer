//
//  DrumStockpileView+List.swift
//  MacStudioServerSimulator
//
//  Sidebar and table surfaces for the drum stockpile workflow.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

extension DrumStockpileView {
    private var sortedGroups: [StockpileGroup] {
        store.groups.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    var groupSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedGroupID) {
                Section(header: Text("Ingest Batches (\(store.groups.count))")) {
                    ForEach(sortedGroups) { group in
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
                            highConfidenceBadge(for: group)
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
                            Divider()
                            Button("Mark as Class A") {
                                store.setHighConfidenceOverride(true, for: group.id)
                            }
                            Button("Remove Class A badge") {
                                store.setHighConfidenceOverride(false, for: group.id)
                            }
                            Button("Reset Class A to Automatic") {
                                store.setHighConfidenceOverride(nil, for: group.id)
                            }
                            Divider()
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
            
            HStack(spacing: 10) {
                Button("Select All Batches") {
                    store.selectedGroupID = nil
                    store.selectedItemIDs = Set(store.items.map(\.id))
                }
                .buttonStyle(.bordered)
                .disabled(store.items.isEmpty)
                
                Button("Mark All Reviewed") {
                    store.markAllReviewed()
                }
                .buttonStyle(.bordered)
                .disabled(store.groups.isEmpty)
                
                Button("Mark All Unreviewed") {
                    store.markAllUnreviewed()
                }
                .buttonStyle(.bordered)
                .disabled(store.groups.isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
    }
    
    private func handleGroupDrop(providers: [NSItemProvider]) -> Bool {
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
    
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
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
    
    @ViewBuilder
    private func highConfidenceBadge(for group: StockpileGroup) -> some View {
        let state = highConfidenceState(for: group)
        if state.active {
            Label("Class A", systemImage: "star.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .foregroundColor(.green)
                .clipShape(Capsule())
                .help(state.reason)
        }
    }
    
    private func highConfidenceState(for group: StockpileGroup) -> (active: Bool, reason: String) {
        if let override = group.highConfidenceOverride {
            if override {
                return (true, "Manually marked as Class A in context menu.")
            } else {
                return (false, "Badge manually hidden in context menu.")
            }
        }
        if inferredHighConfidence(group) {
            return (true, "Auto: all stems have gating disabled.")
        }
        return (false, "Auto: gating active on one or more stems.")
    }
    
    private func inferredHighConfidence(_ group: StockpileGroup) -> Bool {
        guard let items = store.groupedItems[group.id], !items.isEmpty else { return false }
        return items.allSatisfy { !$0.gateSettings.active }
    }
}

// MARK: - Table

extension DrumStockpileView {
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
            .onDrop(of: [.fileURL, .audio], isTargeted: $isDroppingFiles) { providers in
                handleFileDrop(providers: providers)
            }
            .onDeleteCommand {
                let ids = store.selectedItemIDs
                guard !ids.isEmpty else { return }
                store.remove(items: ids)
            }
            
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(6)
            }
        }
    }
    
    private var filteredItems: [StockpileItem] {
        guard let groupID = store.selectedGroupID else { return store.items }
        return store.items.filter { $0.groupID == groupID }
    }
    
    private var sortedItems: [StockpileItem] {
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
    
    private func showInFinder(for itemIDs: Set<UUID>) {
        let targets = store.items.filter { itemIDs.contains($0.id) }
        let urls = targets.map(\.originalURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    
    @ViewBuilder
    private func statusBadge(for status: StockpileStatus) -> some View {
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
    private func classificationMenu(targetIDs: Set<UUID>) -> some View {
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
