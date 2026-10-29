import Foundation

/// Fetches and caches lyrics for the current track.
@MainActor
final class LyricsStore: ObservableObject {
    enum Content: Equatable {
        case idle
        case loading
        case synced([LyricLine])
        case plain([String])
        case instrumental
        case unavailable
        case failed(String)
    }

    @Published private(set) var content: Content = .idle
    private var cache: [String: Content] = [:]
    private var currentKey: String?
    private var task: Task<Void, Never>?
    private let client = LRCLIBClient()

    func load(for track: Track?) {
        guard let track, let key = track.id ?? track.uri else {
            task?.cancel()
            currentKey = nil
            content = .idle
            return
        }
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()
        if let cached = cache[key] {
            content = cached
            return
        }
        content = .loading
        task = Task { [weak self, client] in
            let result: Content
            do {
                let record = try await client.lyrics(
                    title: track.name,
                    artist: track.artists.first?.name ?? "",
                    album: track.album?.name,
                    durationSeconds: Int((Double(track.durationMs) / 1000).rounded())
                )
                result = Self.content(from: record)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                result = .failed("Couldn't load lyrics. \(error.localizedDescription)")
            }
            guard let self, !Task.isCancelled, self.currentKey == key else { return }
            if case .failed = result {} else { self.cache[key] = result }
            self.content = result
        }
    }

    func retry(for track: Track?) {
        if let key = currentKey { cache[key] = nil }
        currentKey = nil
        load(for: track)
    }

    private static func content(from record: LRCLIBClient.Record?) -> Content {
        guard let record else { return .unavailable }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            return .plain(plain.components(separatedBy: .newlines))
        }
        if record.instrumental == true { return .instrumental }
        return .unavailable
    }
}
