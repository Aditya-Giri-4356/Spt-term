import AuthenticationServices
import Combine
import Foundation
import os.log
import UIKit

struct STToken: Codable, Equatable {
    var access: String
    var refresh: String
    var expiresAt: Date

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

enum STAuthError: LocalizedError, CustomStringConvertible, Equatable {
    case cancelled
    case notConfigured
    case malformed
    case missingToken
    case http(status: Int, message: String)

    var description: String {
        switch self {
        case .cancelled: return "cancelled"
        case .notConfigured: return "notConfigured"
        case .malformed: return "malformed"
        case .missingToken: return "missingToken"
        case .http(let status, let message):
            if message.isEmpty {
                return "\(status)"
            }
            return "\(status) \(message)"
        }
    }

    var errorDescription: String? {
        description
    }
}

@MainActor
final class STSpotifyAuth: NSObject {
    @Published private(set) var isAuthorized = false

    private let storageKey = "sptterm.token"
    private var session: ASWebAuthenticationSession?
    private var inFlight: Task<STToken, Error>?
    private var currentPKCE: STPKCE?
    private var inMemoryToken: STToken?

    var authorizedPublisher: AnyPublisher<Bool, Never> {
        $isAuthorized.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        isAuthorized = storedToken() != nil
    }

    func authorize() async throws {
        guard STSpotifyConfig.isConfigured else {
            os_log("STSpotifyAuth.authorize: Spotify is not configured with clientID", log: OSLog.default, type: .error)
            throw STAuthError.notConfigured
        }

        let pkce = STPKCE()
        currentPKCE = pkce
        let callback = try await presentSession(url: authorizationURL(pkce: pkce))
        guard let code = queryValue("code", in: callback) else {
            os_log("STSpotifyAuth.authorize: malformed callback URL (no code query param)", log: OSLog.default, type: .error)
            throw STAuthError.malformed
        }

        let token = try await exchange(code: code, verifier: pkce.verifier)
        persist(token)
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "sptterm" else { return false }
        guard let code = queryValue("code", in: url), let pkce = currentPKCE else { return false }
        Task {
            if let token = try? await exchange(code: code, verifier: pkce.verifier) {
                persist(token)
            }
        }
        return true
    }

    func validToken() async throws -> String {
        let token = storedToken()
        let found = token != nil
        let length = token?.access.count ?? 0
        let isExpired = token?.needsRefresh ?? true
        let expiryDesc = token?.expiresAt.description ?? "nil"

        os_log(
            "STSpotifyAuth.validToken() - Token found: %{public}@, Length: %d, NeedsRefresh/Expired: %{public}@, Expiry: %{public}@",
            log: OSLog.default,
            type: .info,
            found ? "YES" : "NO",
            length,
            isExpired ? "YES" : "NO",
            expiryDesc
        )

        guard let token else {
            os_log("STSpotifyAuth.validToken() - No token found in storage, throwing STAuthError.missingToken", log: OSLog.default, type: .error)
            throw STAuthError.missingToken
        }
        guard token.needsRefresh else { return token.access }

        os_log("STSpotifyAuth.validToken() - Token needs refresh (refresh length: %d)", log: OSLog.default, type: .info, token.refresh.count)

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
        os_log("STSpotifyAuth.withToken() called", log: OSLog.default, type: .debug)
        do {
            let token = try await validToken()
            return try await body(token)
        } catch let STAuthError.http(status, _) where status == 401 {
            os_log("STSpotifyAuth.withToken() - 401 received, forcing token expiry and retrying", log: OSLog.default, type: .info)
            forceExpiry()
            let token = try await validToken()
            return try await body(token)
        }
    }

    func signOut() {
        let deleted = STKeychain.delete(storageKey)
        if !deleted {
            os_log("STSpotifyAuth.signOut: Keychain delete reported failure", log: OSLog.default, type: .error)
        }
        inMemoryToken = nil
        isAuthorized = false
        os_log("STSpotifyAuth.signOut: cleared Keychain and in-memory token, isAuthorized set to false", log: OSLog.default, type: .info)
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
                    os_log("STSpotifyAuth.presentSession error: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    os_log("STSpotifyAuth.presentSession: user cancelled", log: OSLog.default, type: .info)
                    continuation.resume(throwing: STAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                os_log("STSpotifyAuth.presentSession: session.start() returned false", log: OSLog.default, type: .error)
                continuation.resume(throwing: STAuthError.malformed)
            }
        }
    }

    private func exchange(code: String, verifier: String) async throws -> STToken {
        os_log("STSpotifyAuth: Exchanging authorization code for tokens", log: OSLog.default, type: .info)
        return try await tokenRequest(fields: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": STSpotifyConfig.redirectURI,
            "client_id": STSpotifyConfig.clientID,
            "code_verifier": verifier,
        ])
    }

    private func refresh(using refreshToken: String) async throws -> STToken {
        os_log("STSpotifyAuth: Refreshing access token", log: OSLog.default, type: .info)
        return try await tokenRequest(fields: [
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
        guard let http = response as? HTTPURLResponse else {
            os_log("STSpotifyAuth.tokenRequest: response not an HTTPURLResponse", log: OSLog.default, type: .error)
            throw STAuthError.malformed
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "<non-utf8 error body>"
            os_log("STSpotifyAuth.tokenRequest: HTTP %d error: %{public}@", log: OSLog.default, type: .error, http.statusCode, errorBody)
            throw STAuthError.http(status: http.statusCode, message: "/api/token: \(errorBody)")
        }

        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            os_log("STSpotifyAuth.tokenRequest: failed to decode JSON token payload: %{public}@", log: OSLog.default, type: .error, errorBody)
            throw STAuthError.malformed
        }
        return STToken(
            access: payload.access_token,
            refresh: payload.refresh_token ?? storedToken()?.refresh ?? "",
            expiresAt: Date().addingTimeInterval(payload.expires_in)
        )
    }

    private func persist(_ token: STToken) {
        inMemoryToken = token

        var keychainSuccess = false
        if let data = try? JSONEncoder().encode(token),
           let string = String(data: data, encoding: .utf8) {
            keychainSuccess = STKeychain.set(string, for: storageKey)
        } else {
            os_log("STSpotifyAuth.persist: failed to serialize token to JSON string", log: OSLog.default, type: .error)
        }

        os_log(
            "STSpotifyAuth: Token exchange succeeded. Token length: %d, Keychain save: %{public}@, Expiry: %{public}@",
            log: OSLog.default,
            type: .info,
            token.access.count,
            keychainSuccess ? "SUCCESS" : "FAILED",
            token.expiresAt.description
        )

        if !keychainSuccess {
            os_log("STSpotifyAuth: WARNING - Keychain save failed. Using in-memory storage fallback.", log: OSLog.default, type: .default)
        }

        isAuthorized = true
    }

    private func storedToken() -> STToken? {
        if let string = STKeychain.get(storageKey),
           let data = string.data(using: .utf8),
           let token = try? JSONDecoder().decode(STToken.self, from: data) {
            inMemoryToken = token
            return token
        }
        if let memoryToken = inMemoryToken {
            os_log("STSpotifyAuth.storedToken: retrieved token from in-memory storage fallback (length: %d)", log: OSLog.default, type: .debug, memoryToken.access.count)
            return memoryToken
        }
        return nil
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

extension STSpotifyAuth: STAuthServiceProtocol {}
