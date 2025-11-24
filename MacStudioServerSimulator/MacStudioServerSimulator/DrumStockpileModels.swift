//
//  DrumStockpileModels.swift
//  MacStudioServerSimulator
//
//  Data structures for the Drum Stockpile staging area and export manifest.
//

import Foundation
import SwiftUI

enum DrumClass: Hashable, Identifiable, Codable {
    case kick
    case snare
    case hihat
    case tambourine
    case claps
    case toms
    case custom(String)
    
    var id: String {
        switch self {
        case .kick: return "kick"
        case .snare: return "snare"
        case .hihat: return "hihat"
        case .custom(let name): return "other:\(name)"
        case .tambourine: return "tambourine"
        case .claps: return "claps"
        case .toms: return "toms"
        }
    }
    
    var displayName: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hihat: return "Hi-Hat"
        case .tambourine: return "Tambourine"
        case .claps: return "Claps"
        case .toms: return "Toms"
        case .custom(let name):
            return name.isEmpty ? "Other" : name
        }
    }
    
    var manifestLabel: String {
        switch self {
        case .kick: return "kick"
        case .snare: return "snare"
        case .hihat: return "hihat"
        case .tambourine: return "tambourine"
        case .claps: return "claps"
        case .toms: return "toms"
        case .custom(let name):
            let safe = name.replacingOccurrences(of: " ", with: "_")
            return safe.isEmpty ? "other" : safe.lowercased()
        }
    }
    
    var color: Color {
        switch self {
        case .kick:
            return Color.blue
        case .snare:
            return Color.pink
        case .hihat:
            return Color.green
        case .tambourine:
            return Color.orange
        case .claps:
            return Color.cyan
        case .toms:
            return Color.purple
        case .custom(let name):
            // Deterministic pastel based on name hash so customs stay consistent.
            let hash = abs(name.hashValue)
            let hue = Double((hash % 256)) / 255.0
            return Color(hue: hue, saturation: 0.45, brightness: 0.9)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "kick": self = .kick
        case "snare": self = .snare
        case "hihat": self = .hihat
        case "custom":
            let name = try container.decode(String.self, forKey: .name)
            self = .custom(name)
        case "tambourine": self = .tambourine
        case "claps": self = .claps
        case "toms": self = .toms
        default:
            self = .custom("Other")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .kick:
            try container.encode("kick", forKey: .type)
        case .snare:
            try container.encode("snare", forKey: .type)
        case .hihat:
            try container.encode("hihat", forKey: .type)
        case .tambourine:
            try container.encode("tambourine", forKey: .type)
        case .claps:
            try container.encode("claps", forKey: .type)
        case .toms:
            try container.encode("toms", forKey: .type)
        case .custom(let name):
            try container.encode("custom", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

struct GateSettings: Hashable, Codable {
    var threshold: Float = -24 // dB
    var attack: Float = 0.001  // seconds (UI min)
    var release: Float = 0.02  // seconds (UI min)
    var active: Bool = false
}

struct StockpileMetadata: Hashable, Codable {
    var bpm: Double?
    var midiRef: URL?
    var key: String?
    var midiOffset: Double?
}

enum StockpileStatus: String, Codable {
    case pending
    case prepped
    case exported
    case error
}

struct StockpileItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var originalURL: URL
    var classification: DrumClass
    var groupID: UUID
    var gateSettings: GateSettings = GateSettings()
    var metadata: StockpileMetadata = StockpileMetadata()
    var channelCount: Int?
    var status: StockpileStatus = .pending
    var notes: String?
    
    var originalFilename: String {
        originalURL.lastPathComponent
    }
}

struct StockpileGroup: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var reviewed: Bool = false
}

struct StockpileManifestEntry: Codable {
    var id: UUID
    var groupID: UUID
    var classification: String
    var bpm: Double?
    var key: String?
    var midiFilename: String?
    var midiOffset: Double?
    var originalFilename: String
    var outputFilename: String
}

struct StockpileManifest: Codable {
    var version: Int = 1
    var items: [StockpileManifestEntry]
    var createdAt: Date = Date()
}
