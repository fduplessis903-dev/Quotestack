import Foundation

/// One assistant response recorded by Claude Code in ~/.claude/projects/**/*.jsonl.
struct UsageEntry {
    let time: Date
    let model: String
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int

    var tokens: Int { input + output + cacheWrite + cacheRead }
    var cost: Double { Pricing.cost(for: self) }
}

/// Rough API-equivalent pricing (USD per million tokens). Used to weight usage the way
/// plan limits roughly do (Opus output costs far more than Haiku input, etc.).
enum Pricing {
    static func rates(for model: String) -> (input: Double, output: Double) {
        let m = model.lowercased()
        if m.contains("opus") {
            if m.contains("opus-4-1") || m.contains("opus-4-0") || m.contains("opus-4-2025") || m.contains("3-opus") {
                return (15, 75)
            }
            return (5, 25)
        }
        if m.contains("haiku") {
            if m.contains("3-5-haiku") || m.contains("3-haiku") { return (0.8, 4) }
            return (1, 5)
        }
        return (3, 15)
    }

    static func cost(for e: UsageEntry) -> Double {
        let r = rates(for: e.model)
        let total = Double(e.input) * r.input
            + Double(e.output) * r.output
            + Double(e.cacheWrite) * r.input * 1.25
            + Double(e.cacheRead) * r.input * 0.1
        return total / 1_000_000
    }

    /// "claude-opus-4-5-20251101" -> "Opus 4.5", "claude-3-5-sonnet-20241022" -> "Sonnet 3.5"
    static func displayName(_ model: String) -> String {
        var parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let idx = parts.firstIndex(where: { Int($0) == nil }) else { return model }
        let family = parts[idx].capitalized
        parts.remove(at: idx)
        return parts.isEmpty ? family : "\(family) \(parts.joined(separator: "."))"
    }
}

struct DayUsage: Identifiable {
    let day: Date
    let cost: Double
    let tokens: Int
    var id: Date { day }
}

struct ModelUsage: Identifiable {
    let model: String
    let cost: Double
    let tokens: Int
    var id: String { model }
}

struct UsageSummary {
    var sessionActive = false
    var sessionStart: Date?
    var sessionEnd: Date?
    var sessionCost = 0.0
    var sessionTokens = 0
    var sessionBurnPerHour = 0.0
    var busiestPreviousSessionCost = 0.0
    var todayCost = 0.0
    var todayTokens = 0
    var todayModels: [ModelUsage] = []
    var week: [DayUsage] = []
    var foundLogs = false
}

/// Incrementally reads Claude Code's local JSONL logs and summarises usage.
final class UsageStore: ObservableObject {
    @Published private(set) var summary = UsageSummary()
    /// 0 = auto (use your busiest previous 5h session as the 100% mark).
    @Published var sessionLimit: Double {
        didSet { UserDefaults.standard.set(sessionLimit, forKey: "sessionLimit") }
    }

    private let queue = DispatchQueue(label: "claudesidebar.usage", qos: .utility)
    private var offsets: [String: UInt64] = [:]
    private var entries: [String: UsageEntry] = [:]
    private var timer: Timer?
    private let retention: TimeInterval = 8 * 86_400
    private let sessionWindow: TimeInterval = 5 * 3_600

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()
    private static let usageMarker = Data("\"usage\"".utf8)

    init() {
        sessionLimit = UserDefaults.standard.double(forKey: "sessionLimit")
    }

    var effectiveLimit: Double {
        if sessionLimit > 0 { return sessionLimit }
        return max(summary.busiestPreviousSessionCost, summary.sessionCost, 0.01)
    }

    var sessionFraction: Double {
        guard summary.sessionActive else { return 0 }
        return min(summary.sessionCost / effectiveLimit, 1)
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.scan()
            let s = self.summarize(foundLogs: found)
            DispatchQueue.main.async { self.summary = s }
        }
    }

    // MARK: - Reading logs

    private static var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var r = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for p in env.split(separator: ",") {
                let dir = String(p).trimmingCharacters(in: .whitespaces)
                r.append(URL(fileURLWithPath: dir).appendingPathComponent("projects"))
            }
        }
        return r
    }

    private func scan() -> Bool {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-retention)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var found = false
        for root in Self.roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                found = true
                let values = try? url.resourceValues(forKeys: Set(keys))
                if let modified = values?.contentModificationDate, modified < cutoff { continue }
                readNewLines(url: url, size: UInt64(values?.fileSize ?? 0))
            }
        }
        entries = entries.filter { $0.value.time >= cutoff }
        return found
    }

    private func readNewLines(url: URL, size: UInt64) {
        let path = url.path
        var offset = offsets[path] ?? 0
        if size < offset { offset = 0 } // file was rewritten
        guard size > offset, let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: offset) } catch { return }
        guard let data = try? fh.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...lastNewline]
        offsets[path] = offset + UInt64(complete.count)
        for line in complete.split(separator: 0x0A) {
            parse(line: Data(line))
        }
    }

    private func parse(line: Data) {
        guard line.range(of: Self.usageMarker) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let time = Self.isoFrac.date(from: ts) ?? Self.iso.date(from: ts)
        else { return }

        let model = msg["model"] as? String ?? "unknown"
        if model == "<synthetic>" { return }
        func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let entry = UsageEntry(
            time: time, model: model,
            input: int("input_tokens"), output: int("output_tokens"),
            cacheWrite: int("cache_creation_input_tokens"), cacheRead: int("cache_read_input_tokens")
        )
        guard entry.tokens > 0 else { return }
        // The same response can be logged more than once (e.g. resumed sessions) - dedupe.
        let id = msg["id"] as? String ?? obj["uuid"] as? String ?? UUID().uuidString
        entries["\(id)|\(obj["requestId"] as? String ?? "")"] = entry
    }

    // MARK: - Summary

    private func summarize(foundLogs: Bool) -> UsageSummary {
        var s = UsageSummary()
        s.foundLogs = foundLogs
        let now = Date()
        let cal = Calendar.current
        let sorted = entries.values.sorted { $0.time < $1.time }

        // Claude plans meter usage in 5-hour windows that start with your first message.
        struct Block { var start: Date; var cost: Double; var tokens: Int }
        var blocks: [Block] = []
        for e in sorted {
            if let last = blocks.last, e.time < last.start.addingTimeInterval(sessionWindow) {
                blocks[blocks.count - 1].cost += e.cost
                blocks[blocks.count - 1].tokens += e.tokens
            } else {
                let start = cal.dateInterval(of: .hour, for: e.time)?.start ?? e.time
                blocks.append(Block(start: start, cost: e.cost, tokens: e.tokens))
            }
        }
        if let last = blocks.last, now < last.start.addingTimeInterval(sessionWindow) {
            s.sessionActive = true
            s.sessionStart = last.start
            s.sessionEnd = last.start.addingTimeInterval(sessionWindow)
            s.sessionCost = last.cost
            s.sessionTokens = last.tokens
            let hours = max(now.timeIntervalSince(last.start) / 3_600, 1.0 / 60)
            s.sessionBurnPerHour = last.cost / hours
            s.busiestPreviousSessionCost = blocks.dropLast().map(\.cost).max() ?? 0
        } else {
            s.busiestPreviousSessionCost = blocks.map(\.cost).max() ?? 0
        }

        let today = cal.startOfDay(for: now)
        var models: [String: (cost: Double, tokens: Int)] = [:]
        for e in sorted where e.time >= today {
            s.todayCost += e.cost
            s.todayTokens += e.tokens
            let name = Pricing.displayName(e.model)
            let cur = models[name] ?? (0, 0)
            models[name] = (cur.cost + e.cost, cur.tokens + e.tokens)
        }
        s.todayModels = models
            .map { ModelUsage(model: $0.key, cost: $0.value.cost, tokens: $0.value.tokens) }
            .sorted { $0.cost > $1.cost }

        for back in (0..<7).reversed() {
            guard let day = cal.date(byAdding: .day, value: -back, to: today),
                  let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayEntries = sorted.filter { $0.time >= day && $0.time < next }
            s.week.append(DayUsage(
                day: day,
                cost: dayEntries.reduce(0.0) { $0 + $1.cost },
                tokens: dayEntries.reduce(0) { $0 + $1.tokens }
            ))
        }
        return s
    }
}
