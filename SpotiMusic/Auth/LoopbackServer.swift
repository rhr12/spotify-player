import Foundation
import Network

/// A tiny one-shot HTTP server bound to the loopback interface that captures the
/// OAuth redirect (`GET /callback?code=…&state=…`) from the user's browser.
final class LoopbackServer: @unchecked Sendable {
    enum ServerError: LocalizedError {
        case portUnavailable(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .portUnavailable(let reason):
                return "Couldn't listen on 127.0.0.1:\(LoopbackServer.port) (\(reason)). Is another copy of SpotiMusic running?"
            case .cancelled:
                return "Authorization was cancelled."
            }
        }
    }

    static let port: UInt16 = 43824

    private let queue = DispatchQueue(label: "SpotiMusic.LoopbackServer")
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URLComponents, Error>?

    /// Starts listening and suspends until the browser hits `/callback`.
    func waitForCallback() async throws -> URLComponents {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredInterfaceType = .loopback
                let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed(let error) = state {
                        self?.finish(.failure(ServerError.portUnavailable(error.localizedDescription)))
                    }
                }
                self.listener = listener
                listener.start(queue: queue)
            } catch {
                finish(.failure(ServerError.portUnavailable(error.localizedDescription)))
            }
        }
    }

    func cancel() {
        finish(.failure(ServerError.cancelled))
    }

    private func finish(_ result: Result<URLComponents, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        listener?.cancel()
        listener = nil
        continuation?.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let requestLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = requestLine.split(separator: " ")
            let target = parts.count >= 2 ? String(parts[1]) : "/"
            let components = URLComponents(string: "http://127.0.0.1:\(Self.port)\(target)")

            guard let components, components.path == "/callback" else {
                self.respond(connection, status: "404 Not Found", body: "Not found")
                return
            }
            let failed = components.queryItems?.contains { $0.name == "error" } ?? false
            self.respond(connection, status: "200 OK", body: Self.page(success: !failed))
            self.finish(.success(components))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func page(success: Bool) -> String {
        let title = success ? "You're connected." : "Authorization failed."
        let message = success ? "You can close this tab and return to SpotiMusic." : "Return to SpotiMusic and try again."
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>SpotiMusic</title>
        <style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f5f5f7;color:#1d1d1f}
        div{text-align:center}h1{font-size:28px;margin:0 0 8px}p{color:#6e6e73}</style></head>
        <body><div><h1>\(title)</h1><p>\(message)</p></div></body></html>
        """
    }
}
