//
//  ServerModels.swift
//  repapp
//
//  Created on 29/10/2025.
//

import Foundation

// SUMMARY
// Codable models for the local analysis server (Mac Studio) endpoints:
// status/stats, cached analyses, generic responses, and cache export payloads.
// Also includes a tiny AnyCodable to handle dynamic response fields.

// MARK: - Server Status Models

struct ServerStatus: Sendable, Codable {
    let running: Bool
    let port: Int
    let uptime: TimeInterval?
    let version: String

    enum CodingKeys: String, CodingKey {
        case running
        case port
        case uptime
        case version
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        running = try container.decode(Bool.self, forKey: .running)
        port = try container.decode(Int.self, forKey: .port)
        uptime = try container.decodeIfPresent(TimeInterval.self, forKey: .uptime)
        version = try container.decode(String.self, forKey: .version)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(running, forKey: .running)
        try container.encode(port, forKey: .port)
        try container.encodeIfPresent(uptime, forKey: .uptime)
        try container.encode(version, forKey: .version)
    }
}

struct ServerStats: Sendable, Codable {
    let totalAnalyses: Int
    let cacheHits: Int
    let cacheMisses: Int
    let lastUpdated: String?
    let cacheHitRate: String
    let totalCachedSongs: Int?
    let databasePath: String?
}

extension ServerStats {
    enum CodingKeys: String, CodingKey {
        case totalAnalyses = "total_analyses"
        case cacheHits = "cache_hits"
        case cacheMisses = "cache_misses"
        case lastUpdated = "last_updated"
        case cacheHitRate = "cache_hit_rate"
        case totalCachedSongs = "total_cached_songs"
        case databasePath = "database_path"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalAnalyses = try container.decode(Int.self, forKey: .totalAnalyses)
        cacheHits = try container.decode(Int.self, forKey: .cacheHits)
        cacheMisses = try container.decode(Int.self, forKey: .cacheMisses)
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        cacheHitRate = try container.decode(String.self, forKey: .cacheHitRate)
        totalCachedSongs = try container.decodeIfPresent(Int.self, forKey: .totalCachedSongs)
        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalAnalyses, forKey: .totalAnalyses)
        try container.encode(cacheHits, forKey: .cacheHits)
        try container.encode(cacheMisses, forKey: .cacheMisses)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encode(cacheHitRate, forKey: .cacheHitRate)
        try container.encodeIfPresent(totalCachedSongs, forKey: .totalCachedSongs)
        try container.encodeIfPresent(databasePath, forKey: .databasePath)
    }
}

struct CachedAnalysis: Identifiable, Sendable, Codable {
    let id: Int
    let title: String
    let artist: String
    let previewUrl: String
    let bpm: Double?
    let bpmConfidence: Double?
    let key: String?
    let keyConfidence: Double?
    let energy: Double?
    let danceability: Double?
    let acousticness: Double?
    let spectralCentroid: Double?
    let analyzedAt: String
    let analysisDuration: Double?
    let userVerified: Bool
    let manualBpm: Double?
    let manualKey: String?
    let bpmNotes: String?
}

extension CachedAnalysis {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case previewUrl = "preview_url"
        case bpm
        case bpmConfidence = "bpm_confidence"
        case key
        case keyConfidence = "key_confidence"
        case energy
        case danceability
        case acousticness
        case spectralCentroid = "spectral_centroid"
        case analyzedAt = "analyzed_at"
        case analysisDuration = "analysis_duration"
        case userVerified = "user_verified"
        case manualBpm = "manual_bpm"
        case manualKey = "manual_key"
        case bpmNotes = "bpm_notes"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        previewUrl = try container.decode(String.self, forKey: .previewUrl)
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        bpmConfidence = try container.decodeIfPresent(Double.self, forKey: .bpmConfidence)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        keyConfidence = try container.decodeIfPresent(Double.self, forKey: .keyConfidence)
        energy = try container.decodeIfPresent(Double.self, forKey: .energy)
        danceability = try container.decodeIfPresent(Double.self, forKey: .danceability)
        acousticness = try container.decodeIfPresent(Double.self, forKey: .acousticness)
        spectralCentroid = try container.decodeIfPresent(Double.self, forKey: .spectralCentroid)
        analyzedAt = try container.decode(String.self, forKey: .analyzedAt)
        analysisDuration = try container.decodeIfPresent(Double.self, forKey: .analysisDuration)
        userVerified = try container.decode(Bool.self, forKey: .userVerified)
        manualBpm = try container.decodeIfPresent(Double.self, forKey: .manualBpm)
        manualKey = try container.decodeIfPresent(String.self, forKey: .manualKey)
        bpmNotes = try container.decodeIfPresent(String.self, forKey: .bpmNotes)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(previewUrl, forKey: .previewUrl)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encodeIfPresent(bpmConfidence, forKey: .bpmConfidence)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(keyConfidence, forKey: .keyConfidence)
        try container.encodeIfPresent(energy, forKey: .energy)
        try container.encodeIfPresent(danceability, forKey: .danceability)
        try container.encodeIfPresent(acousticness, forKey: .acousticness)
        try container.encodeIfPresent(spectralCentroid, forKey: .spectralCentroid)
        try container.encode(analyzedAt, forKey: .analyzedAt)
        try container.encodeIfPresent(analysisDuration, forKey: .analysisDuration)
        try container.encode(userVerified, forKey: .userVerified)
        try container.encodeIfPresent(manualBpm, forKey: .manualBpm)
        try container.encodeIfPresent(manualKey, forKey: .manualKey)
        try container.encodeIfPresent(bpmNotes, forKey: .bpmNotes)
    }
}

struct ServerResponse: Sendable, Codable {
    let success: Bool
    let message: String?
    let data: [String: AnyCodable]?
}
extension ServerResponse {
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .data)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }
}

struct CachedSong: Sendable, Codable {
    let title: String
    let artist: String
    let bpm: Double
    let key: String
    let energy: Double
    let danceability: Double
    let acousticness: Double
    let analyzedAt: String
}

extension CachedSong {
    enum CodingKeys: String, CodingKey {
        case title, artist, bpm, key, energy, danceability, acousticness
        case analyzedAt = "analyzed_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        bpm = try container.decode(Double.self, forKey: .bpm)
        key = try container.decode(String.self, forKey: .key)
        energy = try container.decode(Double.self, forKey: .energy)
        danceability = try container.decode(Double.self, forKey: .danceability)
        acousticness = try container.decode(Double.self, forKey: .acousticness)
        analyzedAt = try container.decode(String.self, forKey: .analyzedAt)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(key, forKey: .key)
        try container.encode(energy, forKey: .energy)
        try container.encode(danceability, forKey: .danceability)
        try container.encode(acousticness, forKey: .acousticness)
        try container.encode(analyzedAt, forKey: .analyzedAt)
    }
}

struct CacheExportResponse: Sendable, Codable {
    let totalSongs: Int
    let exportedAt: String
    let songs: [CachedSong]
}

extension CacheExportResponse {
    enum CodingKeys: String, CodingKey {
        case totalSongs = "total_songs"
        case exportedAt = "exported_at"
        case songs
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSongs = try container.decode(Int.self, forKey: .totalSongs)
        exportedAt = try container.decode(String.self, forKey: .exportedAt)
        songs = try container.decode([CachedSong].self, forKey: .songs)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalSongs, forKey: .totalSongs)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(songs, forKey: .songs)
    }
}

// Helper for decoding dynamic JSON
struct AnyCodable: Sendable, Codable {
    enum Storage: Sendable, Codable {
        case int(Int)
        case double(Double)
        case string(String)
        case bool(Bool)
        case null
        case array([AnyCodable])
        case dictionary([String: AnyCodable])
        case other(String)
        
        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else if let double = try? container.decode(Double.self) {
                self = .double(double)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let array = try? container.decode([AnyCodable].self) {
                self = .array(array)
            } else if let dictionary = try? container.decode([String: AnyCodable].self) {
                self = .dictionary(dictionary)
            } else if container.decodeNil() {
                self = .null
            } else {
                self = .other("unsupported")
            }
        }
        
        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            case .array(let value):
                try container.encode(value)
            case .dictionary(let value):
                try container.encode(value)
            case .other(let description):
                try container.encode(description)
            }
        }
    }
    
    private let storage: Storage
    
    nonisolated init(storage: Storage) {
        self.storage = storage
    }
    
    nonisolated init(_ value: Any) {
        switch value {
        case let int as Int:
            storage = .int(int)
        case let double as Double:
            storage = .double(double)
        case let string as String:
            storage = .string(string)
        case let bool as Bool:
            storage = .bool(bool)
        case let array as [Any]:
            let wrapped = array.map { AnyCodable($0) }
            storage = .array(wrapped)
        case let dictionary as [String: Any]:
            let wrapped = dictionary.mapValues { AnyCodable($0) }
            storage = .dictionary(wrapped)
        case _ as NSNull:
            storage = .null
        default:
            storage = .other(String(describing: value))
        }
    }
    
    nonisolated init(from decoder: Decoder) throws {
        storage = try Storage(from: decoder)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }
    
    nonisolated var value: Any {
        switch storage {
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let array): return array.map { $0.value }
        case .dictionary(let dictionary):
            return dictionary.mapValues { $0.value }
        case .other(let description): return description
        }
    }
}
