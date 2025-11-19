import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

extension MacStudioServerManager {
// MARK: - Analysis Result Model
    
struct AnalysisResult: Codable {
    let bpm: Double
    let bpmConfidence: Double
    let key: String
    let keyConfidence: Double
    let energy: Double
    let danceability: Double
    let acousticness: Double
    let spectralCentroid: Double
    let analysisDuration: Double
    let cached: Bool
    
    // Phase 1 features (optional for backward compatibility)
    let timeSignature: String?
    let valence: Double?
    let mood: String?
    let loudness: Double?
    let dynamicRange: Double?
    let silenceRatio: Double?
    let keyDetails: JSONValue?
    
    enum CodingKeys: String, CodingKey {
        case bpm
        case bpmConfidence = "bpm_confidence"
        case key
        case keyConfidence = "key_confidence"
        case energy
        case danceability
        case acousticness
        case spectralCentroid = "spectral_centroid"
        case analysisDuration = "analysis_duration"
        case cached
        case timeSignature = "time_signature"
        case valence
        case mood
        case loudness
        case dynamicRange = "dynamic_range"
        case silenceRatio = "silence_ratio"
        case keyDetails = "key_details"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try container.decode(Double.self, forKey: .bpm)
        bpmConfidence = try container.decode(Double.self, forKey: .bpmConfidence)
        key = try container.decode(String.self, forKey: .key)
        keyConfidence = try container.decode(Double.self, forKey: .keyConfidence)
        energy = try container.decode(Double.self, forKey: .energy)
        danceability = try container.decode(Double.self, forKey: .danceability)
        acousticness = try container.decode(Double.self, forKey: .acousticness)
        spectralCentroid = try container.decode(Double.self, forKey: .spectralCentroid)
        analysisDuration = try container.decodeIfPresent(Double.self, forKey: .analysisDuration) ?? 0
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached) ?? false
        timeSignature = try container.decodeIfPresent(String.self, forKey: .timeSignature)
        valence = try container.decodeIfPresent(Double.self, forKey: .valence)
        mood = try container.decodeIfPresent(String.self, forKey: .mood)
        loudness = try container.decodeIfPresent(Double.self, forKey: .loudness)
        dynamicRange = try container.decodeIfPresent(Double.self, forKey: .dynamicRange)
        silenceRatio = try container.decodeIfPresent(Double.self, forKey: .silenceRatio)
        keyDetails = try container.decodeIfPresent(JSONValue.self, forKey: .keyDetails)
    }
}

// MARK: - Generic JSON representation for analyzer metadata

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            var elements: [JSONValue] = []
            while !arrayContainer.isAtEnd {
                let value = try arrayContainer.decode(JSONValue.self)
                elements.append(value)
            }
            self = .array(elements)
            return
        }
        if let objectContainer = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: JSONValue] = [:]
            for key in objectContainer.allKeys {
                dict[key.stringValue] = try objectContainer.decode(JSONValue.self, forKey: key)
            }
            self = .object(dict)
            return
        }
        let singleValue = try decoder.singleValueContainer()
        if singleValue.decodeNil() {
            self = .null
        } else if let boolValue = try? singleValue.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let doubleValue = try? singleValue.decode(Double.self) {
            self = .number(doubleValue)
        } else {
            let stringValue = try singleValue.decode(String.self)
            self = .string(stringValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .array(values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case let .object(dictionary):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
                let codingKey = DynamicCodingKey(stringValue: key)!
                try container.encode(value, forKey: codingKey)
            }
        }
    }

    func jsonString(prettyPrinted: Bool = false) -> String? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }
}

struct AutoManageBanner: Equatable {
    enum Kind: Equatable {
        case info
        case success
        case warning
        case error
    }
    
    let message: String
    let kind: Kind
    let timestamp: Date
}

enum AudioAnalysisError: LocalizedError {
    case serverOffline
    case emptyFile
    case serverError(status: Int, message: String?)
    case fileUnreadable(fileName: String, reason: String)
    
    var errorDescription: String? {
        switch self {
        case .serverOffline:
            return "The analyzer server is offline. Start it from the Servers view or run an analysis to launch it automatically, then try again."
        case .emptyFile:
            return "That file appears to be empty."
        case let .serverError(status, message):
            if let message, !message.isEmpty {
                return "Server error (\(status)): \(message)"
            }
            return "Server error (HTTP \(status))."
        case let .fileUnreadable(fileName, reason):
            return "\(fileName): \(reason)"
        }
    }
}

enum CalibrationWorkflowError: LocalizedError {
    case noSongs
    case builderScriptMissing(String)
    case comparisonScriptMissing(String)
    case spotifyMetricsMissing(String)
    case pythonMissing(String)
    case processFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noSongs:
            return "No calibration songs are available."
        case .builderScriptMissing(let path):
            return "Calibration builder script missing at \(path)."
        case .comparisonScriptMissing(let path):
            return "Comparison script missing at \(path)."
        case .spotifyMetricsMissing(let path):
            return "Spotify metrics CSV not found at \(path)."
        case .pythonMissing(let path):
            return "Python executable not found at \(path)."
        case .processFailed(let output):
            return output.isEmpty ? "Calibration builder failed." : output
        }
    }
}

}
