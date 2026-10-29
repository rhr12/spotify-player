import Foundation

/// A small async/await client for the Spotify Web API with automatic token refresh,
/// 429 back-off and pagination.
@MainActor
final class SpotifyClient {
    struct APIError: LocalizedError {
        let status: Int
        let message: String
        let reason: String?

        var errorDescription: String? {
            switch status {
            case 401: return "Spotify rejected the session. Try signing out and back in."
            case 403:
                if reason == "PREMIUM_REQUIRED" { return "Spotify Premium is required for playback control." }
                return "Spotify denied this request (\(message))."
            case 404 where reason == "NO_ACTIVE_DEVICE" || message.localizedCaseInsensitiveContains("no active device"):
                return "No active Spotify device. Start the built-in player or open Spotify on another device."
            default: return "Spotify error \(status): \(message)"
            }
        }
    }

    static let baseURL = URL(string: "https://api.spotify.com/v1/")!

    private let auth: SpotifyAuth
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(auth: SpotifyAuth) {
        self.auth = auth
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await send("GET", url: url(path, query: query))
        return try decoder.decode(T.self, from: data)
    }

    /// GET that tolerates `204 No Content` (e.g. `/me/player` when nothing is playing).
    func getIfPresent<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T? {
        let data = try await send("GET", url: url(path, query: query))
        guard !data.isEmpty else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    func get<T: Decodable>(absolute url: URL) async throws -> T {
        try decoder.decode(T.self, from: try await send("GET", url: url))
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:], json: [String: Any]? = nil) async throws -> Data {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await send(method, url: url(path, query: query), body: body)
    }

    func post<T: Decodable>(_ path: String, json: [String: Any]) async throws -> T {
        let data = try await send("POST", path, json: json)
        return try decoder.decode(T.self, from: data)
    }

    /// Follows `next` links until exhausted or `maxItems` is reached.
    func allPages<T: Decodable>(_ path: String, query: [String: String] = [:], maxItems: Int = 2000) async throws -> [T] {
        var page: Paging<T> = try await get(path, query: query)
        var items = page.items
        while let next = page.next, let nextURL = URL(string: next), items.count < maxItems {
            page = try await get(absolute: nextURL)
            items += page.items
        }
        return items
    }

    // MARK: Plumbing

    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func send(_ method: String, url: URL, body: Data? = nil, attempt: Int = 0) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try await auth.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200..<300:
            return data
        case 401 where attempt == 0:
            try await auth.refreshAccessToken()
            return try await send(method, url: url, body: body, attempt: attempt + 1)
        case 429 where attempt < 3, 502 where attempt < 2, 503 where attempt < 2:
            let retryAfter = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(attempt + 1)
            try await Task.sleep(nanoseconds: UInt64(min(retryAfter, 10) * 1_000_000_000))
            return try await send(method, url: url, body: body, attempt: attempt + 1)
        default:
            struct Envelope: Decodable {
                struct Body: Decodable { let message: String?; let reason: String? }
                let error: Body?
            }
            let envelope = try? decoder.decode(Envelope.self, from: data)
            throw APIError(
                status: status,
                message: envelope?.error?.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
                reason: envelope?.error?.reason
            )
        }
    }
}
