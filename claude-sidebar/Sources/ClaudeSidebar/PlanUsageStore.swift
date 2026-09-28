import Foundation

/// One of the bars from Claude's Settings → Usage page.
struct PlanLimit: Identifiable {
    let id: String
    let label: String
    let percent: Double // 0...100
    let resetsAt: Date?
}

/// Reads your real plan limits (shared by the Claude app, Cowork and Claude Code) using the
/// login Claude Code saved in your Keychain. The token is only ever sent to api.anthropic.com.
/// This is the same unofficial endpoint Claude Code's /usage screen uses, so it may change.
final class PlanUsageStore: ObservableObject {
    enum Status: Equatable {
        case loading, ok, needsLogin, expired
        case failed(String)
    }

    @Published private(set) var limits: [PlanLimit] = []
    @Published private(set) var status: Status = .loading
    @Published private(set) var updated: Date?

    private let queue = DispatchQueue(label: "claudesidebar.plan", qos: .utility)
    private var timer: Timer?
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    var session: PlanLimit? { limits.first { $0.id == "five_hour" } }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            switch Self.readToken() {
            case .none:
                self.publish(.needsLogin, nil)
            case .expired:
                self.publish(.expired, nil)
            case .token(let token):
                self.fetch(token: token)
            }
        }
    }

    private func fetch(token: String) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                self.publish(.expired, nil)
            } else if error == nil, code == 200, let data, let limits = Self.parse(data) {
                self.publish(.ok, limits)
            } else {
                self.publish(.failed(error?.localizedDescription ?? "HTTP \(code)"), nil)
            }
        }.resume()
    }

    /// On failure the last good numbers stay on screen.
    private func publish(_ status: Status, _ limits: [PlanLimit]?) {
        DispatchQueue.main.async {
            self.status = status
            if let limits {
                self.limits = limits
                self.updated = Date()
            }
        }
    }

    // MARK: - Parsing

    static func parse(_ data: Data) -> [PlanLimit]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let known = [
            ("five_hour", "Current session"),
            ("seven_day", "Weekly · all models"),
            ("seven_day_opus", "Weekly · Opus"),
            ("seven_day_sonnet", "Weekly · Sonnet"),
        ]
        return known.compactMap { key, label in
            guard let entry = obj[key] as? [String: Any],
                  let pct = (entry["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return PlanLimit(id: key, label: label, percent: pct,
                             resetsAt: (entry["resets_at"] as? String).flatMap(parseDate))
        }
    }

    private static let iso = ISO8601DateFormatter()

    private static func parseDate(_ s: String) -> Date? {
        // Drop fractional seconds (e.g. ".123456") which ISO8601DateFormatter can't always read.
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return iso.date(from: trimmed)
    }

    // MARK: - Claude Code login

    private enum TokenResult {
        case none, expired
        case token(String)
    }

    private static func readToken() -> TokenResult {
        let fromFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let json = keychainCredentials()
            ?? (try? String(contentsOf: fromFile, encoding: .utf8))
        guard let data = json?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return .none }
        if let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: expiresMs / 1000) < Date() {
            return .expired
        }
        return .token(token)
    }

    /// Claude Code stores its login with the `security` tool, so asking that same tool
    /// for it avoids a Keychain permission prompt on every rebuild.
    private static func keychainCredentials() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
