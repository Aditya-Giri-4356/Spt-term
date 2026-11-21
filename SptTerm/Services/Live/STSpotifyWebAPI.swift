import Foundation
import os.log

/// Metadata client over the Web API. Playback control lives in
/// `STRemotePlayerService` — the Web API 403s on Free accounts server-side.
final class STSpotifyWebAPI {
    private let auth: STSpotifyAuth

    init(auth: STSpotifyAuth) {
        self.auth = auth
    }

    func search(_ query: String, limit: Int = 20) async throws -> STSearchDTO {
        try await get("search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,album,artist,playlist"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    func album(_ id: String) async throws -> STAlbumPageDTO {
        try await get("albums/\(id)")
    }

    func albumTracks(_ id: String, offset: Int = 0) async throws -> STPagingDTO<STTrackDTO> {
        try await get("albums/\(id)/tracks", query: [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: "50"),
        ])
    }

    func playlist(_ id: String) async throws -> STPlaylistDTO {
        try await get("playlists/\(id)")
    }

    func playlistTracks(_ id: String, offset: Int = 0) async throws -> STPlaylistTracksDTO {
        try await get("playlists/\(id)/tracks", query: [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: "50"),
        ])
    }

    func savedTracks(offset: Int = 0) async throws -> STPagingDTO<STSavedTrackDTO> {
        try await get("me/tracks", query: [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: "50"),
        ])
    }

    func tracks(ids: [String]) async throws -> [STTrackDTO] {
        guard !ids.isEmpty else { return [] }
        let envelope: STTracksEnvelope = try await get("tracks", query: [
            URLQueryItem(name: "ids", value: ids.prefix(50).joined(separator: ",")),
        ])
        return envelope.tracks.compactMap { $0 }
    }

    func saveTrack(_ id: String) async throws {
        try await send("me/tracks", method: "PUT", ids: [id])
    }

    func unsaveTrack(_ id: String) async throws {
        try await send("me/tracks", method: "DELETE", ids: [id])
    }

    func currentUserProfile() async throws -> STUserProfileDTO {
        try await get("me")
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await request(path, method: "GET", query: query, body: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ path: String, method: String, ids: [String]) async throws {
        _ = try await request(
            path,
            method: method,
            query: [],
            body: try JSONEncoder().encode(["ids": ids])
        )
    }

    private func request(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?
    ) async throws -> Data {
        var components = URLComponents(
            url: STSpotifyConfig.apiBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            os_log("STSpotifyWebAPI: Malformed URL for path: %{public}@", log: OSLog.default, type: .error, path)
            throw STAuthError.malformed
        }

        os_log("STSpotifyWebAPI: HTTP Request: %{public}@ %{public}@", log: OSLog.default, type: .info, method, url.absoluteString)

        return try await auth.withToken { token in
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                os_log("STSpotifyWebAPI: Response is not an HTTPURLResponse for %{public}@", log: OSLog.default, type: .error, url.absoluteString)
                throw STAuthError.malformed
            }

            os_log("STSpotifyWebAPI: HTTP Response: %{public}@ %{public}@ -> %d", log: OSLog.default, type: .info, method, url.absoluteString, http.statusCode)

            if !(200..<300).contains(http.statusCode) {
                let errorBody = String(data: data, encoding: .utf8) ?? "<non-utf8 error body>"
                os_log("STSpotifyWebAPI: HTTP %d Error Body: %{public}@", log: OSLog.default, type: .error, http.statusCode, errorBody)

                let extractedMessage = Self.extractErrorMessage(from: data) ?? errorBody
                let pathFormatted = path.hasPrefix("/") ? path : "/\(path)"
                throw STAuthError.http(status: http.statusCode, message: "\(pathFormatted): \(extractedMessage)")
            }
            return data
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct SpotifyErrorPayload: Decodable {
            struct InnerError: Decodable {
                let message: String?
                let status: Int?
            }
            let error: InnerError?
            let error_description: String?
        }
        if let decoded = try? JSONDecoder().decode(SpotifyErrorPayload.self, from: data) {
            return decoded.error?.message ?? decoded.error_description
        }
        return nil
    }
}

extension STSpotifyWebAPI: STSpotifyWebAPIClient {}
