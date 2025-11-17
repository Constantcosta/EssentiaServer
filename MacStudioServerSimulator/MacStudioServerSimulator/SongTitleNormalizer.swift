import Foundation

struct SongTitleNormalizer {
    private static let previewTitleAliasMap: [String: String] = [
        "cyrus prisoner feat dua lipa": "Prisoner (feat. Dua Lipa)",
        "green forget you": "Forget You",
        "song fomerly known as": "! (The Song Formerly Known As)",
        "smith broods 1000x": "1000x",
        "girls 2 become 1": "2 Become 1",
        "20 3am": "3AM",
        "veronicas 4ever": "4ever",
        "parton 9 to 5": "9 to 5",
        "carlton a thousand miles": "A Thousand Miles",
        "perri a thousand years": "A Thousand Years",
        "a whole new world": "A Whole New World (End Title)",
        "about damn time": "About Damn Time"
    ]
    
    static func clean(_ raw: String) -> String {
        var title = raw.replacingOccurrences(of: "_", with: " ")
        while title.contains("  ") {
            title = title.replacingOccurrences(of: "  ", with: " ")
        }
        let trimCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-\"_"))
        title = title.trimmingCharacters(in: trimCharacters)
        
        let normalizedKey = title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = previewTitleAliasMap[normalizedKey] {
            return alias
        }
        return title
    }
}
