import Foundation
import SQLite3

actor CodexThroughputReader {
    struct Turn: Hashable {
        let threadID: UUID
        let turnID: String
    }

    private struct Start {
        let date: Date
        let model: String
        let tier: LocalRequestThroughput.Tier
    }

    private struct Diagnostics {
        var starts: [Turn: [Start]] = [:]
        var responseEnds: [String: Date] = [:]
    }

    private let home: URL
    private let rollouts = CodexRollouts()

    init(home: URL = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap {
        $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.home = home
    }

    func snapshot(now: Date = .now) -> LocalRequestThroughput? {
        // A request can start before the display window and still finish inside it.
        let diagnosticsSince = now.addingTimeInterval(-LocalRequestThroughput.window - 50 * 60)
        guard let diagnostics = readDiagnostics(from: diagnosticsSince, through: now) else { return nil }
        let history = rollouts.read(
            home: home,
            threads: Set(diagnostics.starts.keys.map(\.threadID)),
            since: diagnosticsSince
        )

        var requests: [LocalRequestThroughput.Request] = []
        for (turn, starts) in diagnostics.starts {
            guard let completions = history.completions[turn] else { continue }
            let interruptions = history.interruptions[turn] ?? []
            for (index, start) in starts.enumerated() {
                let nextStart = index + 1 < starts.count ? starts[index + 1].date : now
                let completionsInWindow = completions.filter { $0.date >= start.date && $0.date < nextStart }
                // Diagnostics also contain starts from threads with no persisted usage.
                guard completionsInWindow.count == 1, let completion = completionsInWindow.first,
                      !history.compactions.contains(completion.responseID) else { continue }
                let reading = measure(
                    completion, start: start.date, nextStart: nextStart,
                    interruptions: interruptions,
                    responseEnd: diagnostics.responseEnds[completion.responseID] ?? completion.date
                )
                requests.append(.init(
                    model: start.model, tier: start.tier, startedAt: start.date,
                    completedAt: completion.date, reading: reading
                ))
            }
        }
        return LocalRequestThroughput(requests: requests, now: now)
    }

    private func measure(
        _ completion: CodexRollouts.Completion,
        start: Date,
        nextStart: Date,
        interruptions: [Date],
        responseEnd: Date
    ) -> ThroughputPoint? {
        // Output-item timestamps can arrive after hidden reasoning has already been generated.
        // Use the whole sampling request so the interval covers every token in the usage record.
        guard completion.outputTokens > 0, responseEnd > start, responseEnd < nextStart,
              !interruptions.contains(where: { $0 > start && $0 < responseEnd }) else { return nil }
        let seconds = responseEnd.timeIntervalSince(start)
        return ThroughputPoint(date: completion.date, tps: Double(completion.outputTokens) / seconds)
    }

    private func readDiagnostics(from cutoff: Date, through now: Date) -> Diagnostics? {
        guard let databaseURL = diagnosticsURL() else { return nil }
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        guard opened == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 250)

        let sql = """
            SELECT ts, ts_nanos, thread_id, feedback_log_body
            FROM logs
            WHERE ts BETWEEN ? AND ?
              AND target = 'feedback_tags'
            ORDER BY ts, ts_nanos, id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970.rounded(.down)))
        sqlite3_bind_int64(statement, 2, Int64(now.timeIntervalSince1970.rounded(.down)))

        var result = Diagnostics()
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            defer { status = sqlite3_step(statement) }
            guard let message = sqlite3_column_text(statement, 3) else { continue }
            let body = String(cString: message)
            let detail = body.range(of: "}: ", options: .backwards).map { body[$0.upperBound...] } ?? body[...]
            let seconds = Double(sqlite3_column_int64(statement, 0))
            let nanos = Double(sqlite3_column_int64(statement, 1))
            let date = Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
            guard date >= cutoff, date < now else { continue }
            if detail.hasPrefix("last_model_response_id=\""),
               let id = Self.value(after: "last_model_response_id=\"", in: detail) {
                if result.responseEnds[id] == nil { result.responseEnds[id] = date }
                continue
            }
            guard detail.hasPrefix("model=\""),
                  let model = Self.value(after: "model=\"", in: detail),
                  let thread = sqlite3_column_text(statement, 2),
                  let threadID = UUID(uuidString: String(cString: thread)),
                  let turnID = Self.value(after: "try_run_sampling_request{turn_id=", in: body) else { continue }
            let turn = Turn(threadID: threadID, turnID: turnID)
            let tier = Self.value(after: "\"service_tier\":\"", in: detail)
            result.starts[turn, default: []].append(Start(date: date, model: model, tier: .init(tier)))
        }
        return status == SQLITE_DONE ? result : nil
    }

    private func diagnosticsURL() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let versions = files.compactMap { url -> (Int, URL)? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "sqlite", name.hasPrefix("logs_"),
                  let version = Int(name.dropFirst("logs_".count)) else { return nil }
            return (version, url)
        }
        return versions.max { $0.0 < $1.0 }?.1
    }

    private static func value(after prefix: String, in text: some StringProtocol) -> String? {
        guard let start = text.range(of: prefix)?.upperBound else { return nil }
        let value = text[start...].prefix { $0.isLetter || $0.isNumber || "-_./".contains($0) }
        return value.isEmpty ? nil : String(value)
    }
}
