import Foundation

struct AgentEvent: Identifiable {
    enum Kind { case done, needsInput }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let project: String
    let date: Date

    static var test: AgentEvent {
        AgentEvent(kind: .done, title: "Task done", detail: "This is what a finished Claude Code task looks like.",
                   project: "Test", date: Date())
    }
}

/// Watches ~/.claude/sidebar/events for JSON files written by hooks/sidebar-hook.sh.
final class EventWatcher {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sidebar/events", isDirectory: true)

    var onEvent: ((AgentEvent) -> Void)?
    private let queue = DispatchQueue(label: "claudesidebar.events", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        // Drop anything that piled up while the app wasn't running.
        for url in (try? fm.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(750))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private func poll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil) else { return }
        let ready = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in ready {
            let data = try? Data(contentsOf: url)
            try? fm.removeItem(at: url)
            guard let data, let event = Self.makeEvent(from: data) else { continue }
            DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        }
    }

    static func makeEvent(from data: Data) -> AgentEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let cwd = obj["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent

        switch obj["hook_event_name"] as? String {
        case "Stop":
            let text = obj["last_assistant_message"] as? String
                ?? lastAssistantText(transcriptPath: obj["transcript_path"] as? String)
                ?? "Claude finished responding."
            return AgentEvent(kind: .done, title: "Task done", detail: clip(text), project: project, date: Date())
        case "Notification":
            let msg = obj["message"] as? String ?? "Claude is waiting for you."
            return AgentEvent(kind: .needsInput, title: "Needs your input", detail: clip(msg), project: project, date: Date())
        default:
            return nil
        }
    }

    /// Reads the tail of the session transcript to show what Claude said last.
    private static func lastAssistantText(transcriptPath: String?) -> String? {
        guard let path = transcriptPath,
              let fh = FileHandle(forReadingAtPath: (path as NSString).expandingTildeInPath) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let tail: UInt64 = 256 * 1024
        try? fh.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? fh.readToEnd() else { return nil }
        for line in data.split(separator: 0x0A).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let text = content
                .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    private static func clip(_ s: String, _ limit: Int = 180) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
