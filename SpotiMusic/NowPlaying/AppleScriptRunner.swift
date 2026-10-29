import Foundation

/// Runs AppleScript off the main thread on one serial queue (NSAppleScript isn't thread-safe),
/// caching compiled scripts.
final class AppleScriptRunner: @unchecked Sendable {
    struct ScriptError: Error {
        let code: Int
        let message: String

        /// errAEEventNotPermitted: the user hasn't allowed SpotiMusic to control the app.
        var isPermissionDenied: Bool { code == -1743 || code == -10004 }
    }

    private let queue = DispatchQueue(label: "SpotiMusic.AppleScript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String) async -> Result<NSAppleEventDescriptor, ScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(source))
            }
        }
    }

    private func execute(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else {
                return .failure(ScriptError(code: 0, message: "Invalid script"))
            }
            var compileError: NSDictionary?
            created.compileAndReturnError(&compileError)
            if let compileError {
                return .failure(Self.error(from: compileError))
            }
            compiled[source] = created
            script = created
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return .failure(Self.error(from: error)) }
        return .success(result)
    }

    private static func error(from info: NSDictionary) -> ScriptError {
        ScriptError(
            code: (info[NSAppleScript.errorNumber] as? Int) ?? 0,
            message: (info[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
        )
    }
}

extension NSAppleEventDescriptor {
    /// 1-based list item as a string (AppleScript lists are 1-indexed).
    func string(at index: Int) -> String? {
        guard index <= numberOfItems else { return nil }
        return atIndex(index)?.stringValue
    }

    /// Parses numbers that AppleScript coerced to text, which use the user's decimal separator.
    func number(at index: Int) -> Double? {
        string(at: index).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }
}
