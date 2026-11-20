import Foundation

struct Album: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artistID: String
    let artistName: String
    let year: Int
    let genre: String
    let trackIDs: [String]
    let formatLabel: String
    let summary: String

    var yearLabel: String { String(year) }
}

struct Artist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let albumIDs: [String]
    let trackCount: Int
    let followers: Int
    let popularity: Int
    let isVerified: Bool

    var followersLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: followers)) ?? "\(followers)"
    }

    var popularityLabel: String { "\(popularity)%" }
}
