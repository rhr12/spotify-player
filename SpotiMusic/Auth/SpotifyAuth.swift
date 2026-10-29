import AppKit
import Foundation

/// Spotify OAuth 2.0 Authorization Code flow with PKCE (public client, no secret).
@MainActor
final class SpotifyAuth: ObservableObject {
    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    enum AuthError: LocalizedError {
        case missingClientID
        case stateMismatch
        case denied(String)
        case tokenRequest(String)
        case revoked(String)
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Enter your Spotify Client ID first."
            case .stateMismatch: return "The authorization response didn't match this request. Please try again."
            case .denied(let reason): return reason == "access_denied" ? "Spotify access was denied." : "Spotify returned an error: \(reason)."
            case .tokenRequest(let message), .revoked(let message): return message
            case .notSignedIn: return "You're signed out of Spotify."
            }
        }
    }

    static let redirectURI = "http://127.0.0.1:43824/callback"
    static let scopes = [
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-top-read",
        "user-library-read",
        "user-library-modify",
        "user-follow-read",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-private",
        "playlist-modify-public",
    ]

    private static let clientIDKey = "spotifyClientID"
    private static let tokenAccount = "spotify.tokens"

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey) }
    }
    @Published private(set) var isAuthorized = false
    @Published private(set) var isAuthorizing = false
    @Published var errorMessage: String?

    private var tokens: Tokens?
    private var refreshTask: Task<String, Error>?
    private var server: LoopbackServer?

    init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        if let data = Keychain.get(account: Self.tokenAccount),
           let saved = try? JSONDecoder().decode(Tokens.self, from: data) {
            tokens = saved
            isAuthorized = true
        }
    }

    private var trimmedClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Authorization

    func authorize() async {
        guard !trimmedClientID.isEmpty else {
            errorMessage = AuthError.missingClientID.localizedDescription
            return
        }
        errorMessage = nil
        isAuthorizing = true
        defer { isAuthorizing = false }

        let verifier = PKCE.randomString(length: 96)
        let state = PKCE.randomString(length: 24)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: trimmedClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "state", value: state),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
        ]

        let server = LoopbackServer()
        self.server = server
        defer { self.server = nil }
        async let callback = server.waitForCallback()
        NSWorkspace.shared.open(components.url!)

        do {
            let response = try await callback
            let items = Dictionary(uniqueKeysWithValues: (response.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = items["error"] { throw AuthError.denied(error) }
            guard items["state"] == state else { throw AuthError.stateMismatch }
            guard let code = items["code"] else { throw AuthError.denied("missing code") }
            let tokens = try await requestTokens([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": trimmedClientID,
                "code_verifier": verifier,
            ], previousRefreshToken: nil)
            store(tokens)
            isAuthorized = true
            NSApp.activate(ignoringOtherApps: true)
        } catch LoopbackServer.ServerError.cancelled {
            // User cancelled; nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelAuthorization() {
        server?.cancel()
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        Keychain.delete(account: Self.tokenAccount)
        isAuthorized = false
    }

    // MARK: Tokens

    /// Returns a valid access token, refreshing it silently when it is about to expire.
    func validAccessToken() async throws -> String {
        guard let tokens else { throw AuthError.notSignedIn }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        return try await refreshAccessToken()
    }

    /// Forces a token refresh. Concurrent callers share one network request.
    @discardableResult
    func refreshAccessToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokens else { throw AuthError.notSignedIn }
        let task = Task { () throws -> String in
            let refreshed = try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": trimmedClientID,
            ], previousRefreshToken: current.refreshToken)
            store(refreshed)
            return refreshed.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch AuthError.revoked(let message) {
            // A rejected refresh token means the grant was revoked; require a new sign-in.
            signOut()
            let error = AuthError.revoked(message)
            errorMessage = "Your Spotify session expired. Please connect again. (\(error.localizedDescription))"
            throw error
        }
    }

    private func store(_ tokens: Tokens) {
        self.tokens = tokens
        if let data = try? JSONEncoder().encode(tokens) {
            Keychain.set(data, account: Self.tokenAccount)
        }
    }

    private func requestTokens(_ form: [String: String], previousRefreshToken: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        struct ErrorResponse: Decodable {
            let error: String
            let error_description: String?
        }

        guard status == 200 else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                let message = "Spotify token error: \(err.error_description ?? err.error)"
                throw status == 400 || status == 401 ? AuthError.revoked(message) : AuthError.tokenRequest(message)
            }
            throw AuthError.tokenRequest("Spotify token request failed (HTTP \(status)).")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token ?? previousRefreshToken else {
            throw AuthError.tokenRequest("Spotify did not return a refresh token.")
        }
        return Tokens(
            accessToken: decoded.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        )
    }
}
