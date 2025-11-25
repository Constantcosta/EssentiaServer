import Foundation

public enum DrumClass: Hashable, Identifiable, Codable, Sendable {
    case kick
    case snare
    case hihat
    case tambourine
    case claps
    case toms
    case custom(String)
    
    public var id: String {
        switch self {
        case .kick: return "kick"
        case .snare: return "snare"
        case .hihat: return "hihat"
        case .tambourine: return "tambourine"
        case .claps: return "claps"
        case .toms: return "toms"
        case .custom(let name): return "other:\(name)"
        }
    }
    
    public var displayName: String {
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
    
    public var manifestLabel: String {
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
    
    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "kick": self = .kick
        case "snare": self = .snare
        case "hihat": self = .hihat
        case "tambourine": self = .tambourine
        case "claps": self = .claps
        case "toms": self = .toms
        case "custom":
            let name = try container.decode(String.self, forKey: .name)
            self = .custom(name)
        default:
            self = .custom("Other")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
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

public struct GateSettings: Hashable, Codable, Sendable {
    public var threshold: Float
    public var attack: Float
    public var release: Float
    public var active: Bool
    public var autoApplied: Bool
    
    public init(
        threshold: Float = -24,
        attack: Float = 0.001,
        release: Float = 0.02,
        active: Bool = false,
        autoApplied: Bool = false
    ) {
        self.threshold = threshold
        self.attack = attack
        self.release = release
        self.active = active
        self.autoApplied = autoApplied
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension DrumClass {
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
            let hash = abs(name.hashValue)
            let hue = Double((hash % 256)) / 255.0
            return Color(hue: hue, saturation: 0.45, brightness: 0.9)
        }
    }
}
#endif
