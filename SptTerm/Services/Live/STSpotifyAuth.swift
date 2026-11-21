import AuthenticationServices
import Combine
import Foundation
import UIKit

struct STToken: Codable, Equatable {
    var access: String
    var refresh: String
    var expiresAt: Date

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

enum STAuthError: Error {
    case cancelled
    case notConfigured
    case malformed
    case http(Int)
}

@MainActor
final class STSpotifyAuth: NSObject {
    @Published private(set) var isAuthorized = false

    private let storageKey = "sptterm.token"
    private var session: ASWebAuthenticationSession?
    private var inFlight: Task<STToken, Error>?

    var authorizedPublisher: AnyPublisher<Bool, Never> {
        $isAuthorized.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        isAuthorized = storedToken() != nil
    }

    func authorize() async throws {
        guard STSpotifyConfig.isConfigured else { throw STAuthError.notConfigured }

        let pkce = STPKCE()
        let callback = try await presentSession(url: authorizationURL(pkce: pkce))
        guard let code = queryValue("code", in: callback) else { throw STAuthError.malformed }

        persist(try await exchange(code: code, verifier: pkce.verifier))
    }

    func validToken() async throws -> String {
        guard let token = storedToken() else { throw STAuthError.malformed }
        guard token.needsRefresh else { return token.access }

        if let inFlight { return try await inFlight.value.access }

        let task = Task<STToken, Error> { [refresh = token.refresh] in
            try await self.refresh(using: refresh)
        }
        inFlight = task
        defer { inFlight = nil }

        let refreshed = try await task.value
        persist(refreshed)
        return refreshed.access
    }

    func withToken<T>(_ body: (String) async throws -> T) async throws -> T {
        do {
            return try await body(try await validToken())
        } catch STAuthError.http(401) {
            forceExpiry()
            return try await body(try await validToken())
        }
    }

    func signOut() {
        STKeychain.delete(storageKey)
        isAuthorized = false
    }

    private func authorizationURL(pkce: STPKCE) -> URL {
        var components = URLComponents(
            url: STSpotifyConfig.accountsBase.appendingPathComponent("authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "client_id", value: STSpotifyConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: STSpotifyConfig.redirectURI),
            .init(name: "scope", value: STSpotifyConfig.scopeString),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: pkce.challenge),
        ]
        return components.url!
    }

    private func presentSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "sptterm"
            ) { callback, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: STAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                continuation.resume(throwing: STAuthError.malformed)
            }
        }
    }

    private func exchange(code: String, verifier: String) async throws -> STToken {
        try await tokenRequest(fields: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": STSpotifyConfig.redirectURI,
            "client_id": STSpotifyConfig.clientID,
            "code_verifier": verifier,
        ])
    }

    private func refresh(using refreshToken: String) async throws -> STToken {
        try await tokenRequest(fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": STSpotifyConfig.clientID,
        ])
    }

    private func tokenRequest(fields: [String: String]) async throws -> STToken {
        var request = URLRequest(
            url: STSpotifyConfig.accountsBase.appendingPathComponent("api/token")
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(
                    withAllowedCharacters: .alphanumerics
                ) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw STAuthError.malformed }
        guard (200..<300).contains(http.statusCode) else { throw STAuthError.http(http.statusCode) }

        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else {
            throw STAuthError.malformed
        }
        return STToken(
            access: payload.access_token,
            refresh: payload.refresh_token ?? storedToken()?.refresh ?? "",
            expiresAt: Date().addingTimeInterval(payload.expires_in)
        )
    }

    private func persist(_ token: STToken) {
        guard let data = try? JSONEncoder().encode(token),
              let string = String(data: data, encoding: .utf8) else { return }
        STKeychain.set(string, for: storageKey)
        isAuthorized = true
    }

    private func storedToken() -> STToken? {
        guard let string = STKeychain.get(storageKey),
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(STToken.self, from: data)
    }

    private func forceExpiry() {
        guard var token = storedToken() else { return }
        token.expiresAt = .distantPast
        persist(token)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private struct TokenPayload: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }
}

extension STSpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
