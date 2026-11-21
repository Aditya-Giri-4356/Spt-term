import Foundation

struct STImageDTO: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

struct STArtistDTO: Decodable {
    let id: String?
    let name: String
}

struct STAlbumDTO: Decodable {
    let id: String
    let name: String
    let release_date: String?
    let images: [STImageDTO]?
    let artists: [STArtistDTO]?
}

struct STTrackDTO: Decodable {
    let id: String
    let name: String
    let duration_ms: Int
    let track_number: Int?
    let artists: [STArtistDTO]?
    let album: STAlbumDTO?
}

struct STOwnerDTO: Decodable {
    let id: String?
    let display_name: String?
}

struct STUserProfileDTO: Decodable {
    let id: String
    let display_name: String?
    let product: String?
    let email: String?
}

struct STPlaylistDTO: Decodable {
    let id: String
    let name: String
    let owner: STOwnerDTO?
    let images: [STImageDTO]?
    let tracks: STPlaylistTracksDTO?
}

struct STPlaylistTracksDTO: Decodable {
    let total: Int?
    let items: [STPlaylistItemDTO]?
}

struct STPlaylistItemDTO: Decodable {
    let track: STTrackDTO?
}

struct STSavedTrackDTO: Decodable {
    let track: STTrackDTO
}

struct STPagingDTO<Item: Decodable>: Decodable {
    let items: [Item]
    let next: String?
    let total: Int?
}

struct STTracksEnvelope: Decodable {
    let tracks: [STTrackDTO?]
}

struct STSearchDTO: Decodable {
    let tracks: STPagingDTO<STTrackDTO>?
    let albums: STPagingDTO<STAlbumDTO>?
    let artists: STPagingDTO<STArtistDTO>?
    let playlists: STPagingDTO<STPlaylistDTO>?
}

struct STAlbumPageDTO: Decodable {
    let id: String
    let name: String
    let release_date: String?
    let images: [STImageDTO]?
    let artists: [STArtistDTO]?
    let tracks: STPagingDTO<STTrackDTO>?
}
