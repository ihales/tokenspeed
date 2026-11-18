import Foundation
import SQLite3
import Testing
@testable import TokenSpeed

@MainActor @Test func localModelNamesUseReadableFallbacksWithoutTheCatalog() {
    let store = MonitorStore(historyURL: nil)
    #expect(store.localModelName(for: "gpt-6.2-sol") == "GPT-6.2 Sol")
    #expect(store.localModelName(for: "gpt-6.1-sol") == "GPT-6.1 Sol")
    #expect(store.localModelName(for: "gpt-6.1-sol-20261002") == "GPT-6.1 Sol")
    #expect(store.localModelName(for: "gpt-4o-mini") == "GPT-4o Mini")
    #expect(store.localModelName(for: "claude-haiku-4-5") == "Claude Haiku 4.5")
    #expect(store.localModelName(for: "custom-model") == "custom-model")
}

@Test func recentRequestsGroupByModelAndAverageEachTier() {
    let now = Date(timeIntervalSince1970: 1000)
    func request(_ model: String, _ tier: String, age: TimeInterval, tps: Double?) -> LocalRequestThroughput.Request {
        let finished = now.addingTimeInterval(-age)
        return .init(model: model, tier: .init(tier), startedAt: finished.addingTimeInterval(-2), completedAt: finished,
                     reading: tps.map { ThroughputPoint(date: finished, tps: $0) })
    }
    let snapshot = LocalRequestThroughput(requests: [
        request("sol", "priority", age: 12, tps: 75),
        request("sol", "fast", age: 32, tps: 105),
        request("sol", "default", age: 400, tps: 50),
        request("sol", "ultrafast", age: 12.5, tps: nil),
        request("sol", "fast", age: 3601, tps: 800),
        request("astra", "default", age: 1800, tps: 30)
    ], now: now)

    #expect(snapshot.models.map(\.id) == ["sol", "astra"])
    #expect(snapshot.models[1].readings.map(\.average) == [30])
    #expect(snapshot.models[0].readings.map(\.tier) == [.fast, .ultrafast, .standard])
    #expect(snapshot.models[0].readings[0].points.map(\.tps) == [105, 75])
    #expect(snapshot.models[0].readings[0].average == 90)
    #expect(snapshot.models[0].readings[1].average == nil)
}

@Test func requestTimingIncludesFirstOutputDelayAndExcludesToolWaits() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sessions = home.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let thread = UUID().uuidString.lowercased()
    let turn = "test-turn"
    let epoch: Int64 = 1_700_000_000
    let scope = "turn{}:try_run_sampling_request{turn_id=\(turn) model=sol}:"
    let feedback = "feedback_tags"
    let stream = "codex_core::stream_events_utils"
    var database: OpaquePointer?
    let opened = sqlite3_open(home.appendingPathComponent("logs_2.sqlite").path, &database)
    defer { sqlite3_close(database) }
    try #require(opened == SQLITE_OK)

    func sql(_ statement: String) throws {
        let code = sqlite3_exec(database, statement, nil, nil, nil)
        try #require(code == SQLITE_OK)
    }
    try sql("""
        CREATE TABLE logs (id INTEGER PRIMARY KEY, ts INTEGER, ts_nanos INTEGER,
                           target TEXT, thread_id TEXT, feedback_log_body TEXT)
        """)
    func log(_ offset: Int64, _ target: String, _ detail: String, scoped: Bool = true) throws {
        let owner = scoped ? "'\(thread)'" : "NULL"
        let body = scoped ? "\(scope) \(detail)" : detail
        try sql("INSERT INTO logs (ts, ts_nanos, target, thread_id, feedback_log_body) VALUES (\(epoch + offset), 0, '\(target)', \(owner), '\(body)')")
    }
    func start(_ offset: Int64, tier: String) throws {
        try log(offset, feedback, #"model="sol" tags_json={"service_tier":"\#(tier)"}"#)
    }
    func output(_ offset: Int64) throws {
        try log(offset, stream, #"Output item item_type="reasoning""#)
    }
    try start(10, tier: "default")
    try output(19)
    try log(20, feedback, #"last_model_response_id="response-a""#, scoped: false)
    try start(100, tier: "priority")
    try output(101)
    try start(120, tier: "ultrafast")
    try output(122)
    try start(150, tier: "default")
    try output(151)
    try start(170, tier: "flex")
    let transientThread = UUID().uuidString
    try sql("""
        INSERT INTO logs (ts, ts_nanos, target, thread_id, feedback_log_body)
        VALUES (\(epoch + 180), 0, '\(feedback)', '\(transientThread)',
                '\(scope) model="unmatched-model" tags_json={"service_tier":"default"}')
        """)

    func record(_ offset: Int64, type: String, payload: String) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch + offset))
        let stamp = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return #"{"timestamp":"\#(stamp)","ordinal":\#(offset),"type":"\#(type)","payload":\#(payload)}"# + "\n"
    }
    func usage(_ offset: Int64, _ id: String, _ tokens: Int) -> String {
        record(offset, type: "token_usage_record",
               payload: #"{"thread_id":"\#(thread)","turn_id":"\#(turn)","response_id":"\#(id)","usage":{"output_tokens":\#(tokens)}}"#)
    }
    func toolResult(_ offset: Int64, large: Bool = false) -> String {
        record(offset, type: "response_item",
               payload: #"{"type":"custom_tool_call_output","output":"\#(large ? String(repeating: "a", count: 300_000) : "ok")","internal_chat_message_metadata_passthrough":{"turn_id":"\#(turn)"}}"#)
    }
    let rollout = usage(21, "response-a", 200) + toolResult(99, large: true)
        + usage(103, "response-b", 300) + usage(104, "response-c", 100)
        + toolResult(123) + usage(124, "response-d", 300)
        + usage(153, "response-e", 360) + usage(153, "response-e", 360)
    try rollout.write(to: sessions.appendingPathComponent("rollout-\(thread).jsonl"), atomically: true, encoding: .utf8)

    let reader = CodexThroughputReader(home: home)
    let snapshot = try #require(await reader.snapshot(now: Date(timeIntervalSince1970: TimeInterval(epoch + 200))))
    #expect(snapshot.models.map(\.id) == ["sol"])
    #expect(snapshot.models[0].readings.map(\.tier) == [.standard, .ultrafast])
    #expect(snapshot.models[0].readings[0].points.map(\.tps) == [20, 120])
    #expect(snapshot.models[0].readings[0].average == 70)
    #expect(snapshot.models[0].readings[1].points.isEmpty)
}
