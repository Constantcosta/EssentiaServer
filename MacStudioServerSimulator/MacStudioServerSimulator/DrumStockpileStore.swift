//
//  DrumStockpileStore.swift
//  MacStudioServerSimulator
//
//  Observable state + persistence for the Drum Stockpile staging area.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class DrumStockpileStore: ObservableObject {
    @Published var groups: [StockpileGroup] = []
    @Published var items: [StockpileItem] = []
    @Published var selectedGroupID: UUID?
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var errorMessage: String?
    @Published var lastExportURL: URL?
    
    private let supportedAudioExtensions: Set<String> = ["wav", "aiff", "aif", "flac", "mp3", "m4a", "aifc", "caf"]
    private let baseDirectory: URL
    private let stateURL: URL
    private let fileManager = FileManager.default
    
    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
        fileManager.temporaryDirectory
        baseDirectory = appSupport.appendingPathComponent("DrumStockpile", isDirectory: true)
        stateURL = baseDirectory.appendingPathComponent("stockpile_state.json")
        ensureDirectories()
        loadState()
        if groups.isEmpty {
            let defaultGroup = StockpileGroup(name: "Ungrouped")
            groups.append(defaultGroup)
            selectedGroupID = defaultGroup.id
        }
    }
    
    // MARK: - Persistence
    
    private func ensureDirectories() {
        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Unable to prepare Application Support folder: \(error.localizedDescription)"
        }
    }
    
    private func loadState() {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        do {
            let data = try Data(contentsOf: stateURL)
            let decoded = try JSONDecoder().decode(StatePayload.self, from: data)
            groups = decoded.groups
            items = decoded.items
            selectedGroupID = decoded.selectedGroupID ?? groups.first?.id
        } catch {
            errorMessage = "Failed to load stockpile state: \(error.localizedDescription)"
        }
    }
    
    private func persistState() {
        let payload = StatePayload(groups: groups, items: items, selectedGroupID: selectedGroupID)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            errorMessage = "Failed to save stockpile state: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Groups
    
    func createGroup(fromFolder url: URL) {
        let groupName = url.lastPathComponent
        let group = StockpileGroup(name: groupName)
        groups.append(group)
        selectedGroupID = group.id
        ingest(urls: [url], assignGroup: group.id)
        persistState()
    }
    
    func createGroup(named name: String) -> StockpileGroup {
        let group = StockpileGroup(name: name)
        groups.append(group)
        selectedGroupID = group.id
        persistState()
        return group
    }
    
    func toggleReviewed(_ groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].reviewed.toggle()
        persistState()
    }
    
    func renameGroup(_ groupID: UUID, to newName: String) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        groups[idx].name = trimmed
        persistState()
    }
    
    // MARK: - Ingest
    
    func ingest(urls: [URL], assignGroup groupID: UUID? = nil) {
        var targetGroup = groupID ?? selectedGroupID ?? groups.first?.id ?? createGroup(named: "Ungrouped").id
        for url in urls {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                ingestDirectory(url, assignGroup: targetGroup)
            } else {
                let parentName = url.deletingLastPathComponent().lastPathComponent
                if let inferred = applyInferredGroupName(forParent: parentName, currentGroup: targetGroup) {
                    targetGroup = inferred
                } else {
                    targetGroup = groupID ?? selectedGroupID ?? targetGroup
                }
                ingestFile(url, assignGroup: targetGroup)
            }
        }
        if !urls.isEmpty {
            applyInferredGroupName(from: urls, to: targetGroup)
        }
        persistState()
    }
    
    private func ingestDirectory(_ url: URL, assignGroup groupID: UUID?) {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            ingestFile(fileURL, assignGroup: groupID)
        }
    }
    
    private func ingestFile(_ url: URL, assignGroup groupID: UUID?) {
        guard supportedAudioExtensions.contains(url.pathExtension.lowercased()) else { return }
        let targetGroup = groupID ?? selectedGroupID ?? groups.first?.id ?? createGroup(named: "Ungrouped").id
        let channelCount = readChannelCount(for: url)
        let inferredClass = inferClass(from: url.lastPathComponent)
        let item = StockpileItem(
            originalURL: url,
            classification: inferredClass,
            groupID: targetGroup,
            gateSettings: GateSettings(),
            metadata: StockpileMetadata(),
            channelCount: channelCount,
            status: .pending,
            notes: nil
        )
        items.append(item)
    }
    
    private func readChannelCount(for url: URL) -> Int? {
        do {
            let file = try AVAudioFile(forReading: url)
            return Int(file.fileFormat.channelCount)
        } catch {
            return nil
        }
    }
    
    // MARK: - Item Updates
    
    func updateClassification(for itemIDs: Set<UUID>, to newClass: DrumClass) {
        items = items.map { item in
            guard itemIDs.contains(item.id) else { return item }
            var copy = item
            copy.classification = newClass
            return copy
        }
        persistState()
    }
    
    func updateGroup(for itemIDs: Set<UUID>, to groupID: UUID) {
        items = items.map { item in
            guard itemIDs.contains(item.id) else { return item }
            var copy = item
            copy.groupID = groupID
            return copy
        }
        persistState()
    }
    
    func updateMetadata(for itemID: UUID, metadata: StockpileMetadata) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].metadata = metadata
        persistState()
    }
    
    func updateMetadata(for itemIDs: Set<UUID>, bpm: Double?, key: String?) {
        items = items.map { item in
            guard itemIDs.contains(item.id) else { return item }
            var updated = item
            if let bpm { updated.metadata.bpm = bpm }
            if let key { updated.metadata.key = key.isEmpty ? nil : key }
            return updated
        }
        persistState()
    }
    
    func updateGate(for itemID: UUID, gate: GateSettings) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].gateSettings = gate
        persistState()
    }
    
    func markStatus(_ status: StockpileStatus, for itemID: UUID) {
        markStatus(status, for: [itemID])
    }
    
    func markStatus(_ status: StockpileStatus, for itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        items = items.map { item in
            guard itemIDs.contains(item.id) else { return item }
            var copy = item
            copy.status = status
            return copy
        }
        persistState()
    }
    
    func remove(items itemIDs: Set<UUID>) {
        items.removeAll { itemIDs.contains($0.id) }
        selectedItemIDs.subtract(itemIDs)
        persistState()
    }

    // MARK: - Group name inference
    
    private func applyInferredGroupName(from urls: [URL], to groupID: UUID?) {
        guard let groupID, let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let parentNames = Set(
            urls
                .filter { !$0.hasDirectoryPath }
                .map { $0.deletingLastPathComponent().lastPathComponent }
        )
        guard parentNames.count == 1, let inferred = parentNames.first, !inferred.isEmpty else { return }
        
        // Only rename if the group is still generic.
        let existingName = groups[groupIndex].name
        if existingName == "Ungrouped" || existingName.hasPrefix("Batch ") || existingName.isEmpty {
            groups[groupIndex].name = inferred
        }
    }

    // If ingesting single files with a shared parent folder, try to reuse/rename the current group
    // to that folder name when it is still generic.
    @discardableResult
    private func applyInferredGroupName(forParent parent: String, currentGroup: UUID?) -> UUID? {
        guard !parent.isEmpty else { return currentGroup }
        guard let currentGroup, let idx = groups.firstIndex(where: { $0.id == currentGroup }) else { return currentGroup }
        let existing = groups[idx].name
        if existing == "Ungrouped" || existing.hasPrefix("Batch ") || existing.isEmpty {
            groups[idx].name = parent
            return currentGroup
        }
        return currentGroup
    }
    
    // MARK: - Filename-based class inference
    
    private func inferClass(from filename: String) -> DrumClass {
        let lower = filename.lowercased()
        func contains(_ terms: [String]) -> Bool {
            terms.contains { lower.contains($0) }
        }
        
        if contains(["kick", "bd", "bassdrum"]) { return .kick }
        if contains(["snare", "snr"]) { return .snare }
        if contains(["hihat", "hi-hat", "hat", "hh"]) { return .hihat }
        if contains(["tamb", "tambourine"]) { return .tambourine }
        if contains(["clap", "claps"]) { return .claps }
        if contains(["tom", "toms"]) { return .toms }
        if contains(["ride"]) { return .custom("Ride") }
        if contains(["crash", "splash", "china", "cym"]) { return .custom("Cymbal") }
        if contains(["perc", "percussion"]) { return .custom("Perc") }
        return .custom("Other")
    }
    
    // MARK: - Export
    
    func commit(to destination: URL) async {
        let exportItems = items
        guard !exportItems.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        errorMessage = nil
        do {
            let manifest: StockpileManifest = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StockpileManifest, Error>) in
                Task.detached(priority: .userInitiated) { [weak self] in
                    do {
                        let manifest = try await DrumStockpileExporter.export(
                            items: exportItems,
                            destination: destination
                        ) { progress in
                            Task { @MainActor in
                                self?.exportProgress = progress
                            }
                        }
                        continuation.resume(returning: manifest)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let manifestURL = destination.appendingPathComponent("dataset.json")
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL, options: Data.WritingOptions.atomic)
            lastExportURL = destination
            exportProgress = 1
            items = items.map { var item = $0; item.status = .exported; return item }
            persistState()
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
        isExporting = false
    }
    
    // MARK: - Helpers
    
    var selectedItems: [StockpileItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }
    
    var groupedItems: [UUID: [StockpileItem]] {
        Dictionary(grouping: items, by: { $0.groupID })
    }
}

private struct StatePayload: Codable {
    let groups: [StockpileGroup]
    let items: [StockpileItem]
    let selectedGroupID: UUID?
}
