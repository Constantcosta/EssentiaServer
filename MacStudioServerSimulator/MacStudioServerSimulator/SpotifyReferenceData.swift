//
//  SpotifyReferenceData.swift
//  MacStudioServerSimulator
//
//  Spotify reference data for comparison with analysis results
//

import Foundation

/// Represents a single Spotify track with its metadata
struct SpotifyTrack: Codable, Identifiable {
    var id: String { spotifyTrackId }
    
    let song: String
    let artist: String
    let bpm: Int
    let key: String
    let spotifyTrackId: String
    let testSet: String  // "preview" or "fullsong"
    
    // Optional fields we might use later
    let popularity: Int?
    let dance: Int?
    let energy: Int?
    let acoustic: Int?
    let happy: Int?
    let loudDb: Int?
    
    enum CodingKeys: String, CodingKey {
        case song = "Song"
        case artist = "Artist"
        case bpm = "BPM"
        case key = "Key"
        case spotifyTrackId = "Spotify Track Id"
        case testSet
        case popularity = "Popularity"
        case dance = "Dance"
        case energy = "Energy"
        case acoustic = "Acoustic"
        case happy = "Happy"
        case loudDb = "Loud (Db)"
    }
}

/// Manager for Spotify reference data
class SpotifyReferenceData {
    static let shared = SpotifyReferenceData()
    
    private var tracks: [SpotifyTrack] = []
    private var trackLookup: [String: SpotifyTrack] = [:]  // Key: "song|artist"
    private var songLookup: [String: SpotifyTrack] = [:]   // Key: normalized song only
    private let resourceResolver: (_ filename: String, _ fileExtension: String) -> URL?
    
    init(resourceResolver: @escaping (_ filename: String, _ fileExtension: String) -> URL? = { filename, fileExtension in
        Bundle.main.url(forResource: filename, withExtension: fileExtension)
    }) {
        self.resourceResolver = resourceResolver
        loadReferenceData()
    }
    
    /// Load Spotify reference data from embedded CSV files
    private func loadReferenceData() {
        // Load both CSV files
        loadCSV(filename: "test_12_preview", testSet: "preview")
        loadCSV(filename: "test_12_fullsong", testSet: "fullsong")
        
        print("📊 Loaded \(tracks.count) Spotify reference tracks")
        print("📊 songLookup has \(songLookup.count) entries")
        print("📊 trackLookup has \(trackLookup.count) entries")
        
        // Debug: print first few song keys
        for (key, track) in songLookup.prefix(5) {
            print("  🔑 '\(key)' -> '\(track.song)' by '\(track.artist)'")
        }
    }
    
    /// Load a specific CSV file
    private func loadCSV(filename: String, testSet: String) {
        guard let csvURL = resourceResolver(filename, "csv") else {
            print("⚠️ Could not find \(filename).csv in bundle")
            return
        }
        
        do {
            let csvString = try String(contentsOf: csvURL, encoding: .utf8)
            let rows = csvString.components(separatedBy: .newlines)
            
            // Skip header row
            guard rows.count > 1 else { return }
            
            for row in rows[1...] {
                guard !row.isEmpty else { continue }
                
                // Parse CSV row (using simple split - could use proper CSV parser if needed)
                let columns = parseCSVRow(row)
                
                guard columns.count >= 24 else { continue }
                
                // Extract relevant fields (based on CSV structure)
                let song = columns[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                let artist = columns[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                let bpmString = columns[4].trimmingCharacters(in: .whitespaces)
                let key = columns[18].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                let trackId = columns[21].trimmingCharacters(in: .whitespaces)
                
                guard let bpm = Int(bpmString), !trackId.isEmpty else { continue }
                
                let track = SpotifyTrack(
                    song: song,
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    spotifyTrackId: trackId,
                    testSet: testSet,
                    popularity: Int(columns[3]),
                    dance: Int(columns[10]),
                    energy: Int(columns[11]),
                    acoustic: Int(columns[12]),
                    happy: Int(columns[14]),
                    loudDb: Int(columns[17])
                )
                
                tracks.append(track)
                
                // Create lookup key (normalized)
                let lookupKey = makeLookupKey(song: song, artist: artist)
                trackLookup[lookupKey] = track
                let songKey = normalizeSong(song)
                if songLookup[songKey] == nil {
                    songLookup[songKey] = track
                }
            }
            
            print("✅ Loaded \(tracks.filter { $0.testSet == testSet }.count) tracks from \(filename)")
            
        } catch {
            print("❌ Error loading \(filename).csv: \(error)")
        }
    }
    
    /// Parse a CSV row handling quoted fields
    private func parseCSVRow(_ row: String) -> [String] {
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false
        
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(currentColumn)
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }
        }
        columns.append(currentColumn)  // Add last column
        
        return columns
    }
    
    /// Normalize song title for lookups
    private func normalizeSong(_ song: String) -> String {
        return song.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }
    
    /// Normalize artist name for lookups
    private func normalizeArtist(_ artist: String) -> String {
        return artist.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }
    
    /// Create normalized lookup key from song and artist
    private func makeLookupKey(song: String, artist: String) -> String {
        let normalizedSong = normalizeSong(song)
        let normalizedArtist = normalizeArtist(artist)
        return "\(normalizedSong)|\(normalizedArtist)"
    }
    
    /// Find Spotify reference track by song and artist
    func findTrack(song: String, artist: String) -> SpotifyTrack? {
        let lookupKey = makeLookupKey(song: song, artist: artist)
        if let track = trackLookup[lookupKey] {
            return track
        }
        
        let normalizedSong = normalizeSong(song)
        if let track = songLookup[normalizedSong] {
            return track
        }
        
        if let baseTitle = song.components(separatedBy: " - ").first, baseTitle.count > 2 {
            let baseKey = normalizeSong(baseTitle)
            if let track = songLookup[baseKey] {
                return track
            }
        }
        
        return nil
    }
    
    /// Get all tracks for a specific test set
    func getTracks(forTestSet testSet: String) -> [SpotifyTrack] {
        return tracks.filter { $0.testSet == testSet }
    }
    
    /// Get all preview tracks
    var previewTracks: [SpotifyTrack] {
        getTracks(forTestSet: "preview")
    }
    
    /// Get all fullsong tracks
    var fullsongTracks: [SpotifyTrack] {
        getTracks(forTestSet: "fullsong")
    }
    
    /// Get all tracks
    var allTracks: [SpotifyTrack] {
        tracks
    }
}
