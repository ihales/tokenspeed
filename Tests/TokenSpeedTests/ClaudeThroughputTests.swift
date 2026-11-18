import Foundation
import Testing
@testable import TokenSpeed

@MainActor @Test func claudeUsesOneCompletedResponsePerAPIRequestAndKeepsSpeedModesSeparate() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let project = home.appendingPathComponent("projects/example", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let base = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down) - 100)
    let file = project.appendingPathComponent("session.jsonl")
    let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    func line(_ offset: TimeInterval, _ fields: String) -> String {
        let timestamp = iso.format(base.addingTimeInterval(offset))
        return #"{"timestamp":"\#(timestamp)",\#(fields)}"# + "\n"
    }

    func start(_ offset: TimeInterval, _ request: String) -> String {
        line(offset, #""type":"api-request","id":"\#(request)""#)
    }

    func response(
        _ offset: TimeInterval, _ request: String, message: String? = nil, tokens: Int, speed: String
    ) -> String {
        line(offset, #""type":"assistant","requestRef":"\#(request)","message":{"id":"\#(message ?? request)","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"output_tokens":\#(tokens),"speed":"\#(speed)"}}"#)
    }

    let transcript = [
        start(0, "request-a"),
        response(1, "request-a", tokens: 70, speed: "standard"),
        response(4, "request-a", tokens: 240, speed: "standard"),
        line(70, #""type":"user","message":{"content":[{"type":"tool_result"}]}"#),
        start(70, "request-b"),
        response(73, "request-b", tokens: 300, speed: "fast"),
        start(90, "ambiguous"),
        response(91, "ambiguous", message: "message-c", tokens: 600, speed: "fast"),
        response(92, "ambiguous", message: "message-d", tokens: 600, speed: "fast"),
        response(95, "missing-start", tokens: 600, speed: "fast")
    ].joined()
    try transcript.write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.copyItem(at: file, to: project.appendingPathComponent("copy.jsonl"))

    let reader = ClaudeThroughputReader(home: home)
    let snapshot = try #require(await reader.snapshot(now: base.addingTimeInterval(100)))
    #expect(snapshot.models.map(\.id) == ["claude-opus-5-5"])
    #expect(snapshot.models[0].readings.map(\.tier) == [.fast, .standard])
    #expect(snapshot.models[0].readings.map { $0.points.count } == [1, 1])
    #expect(snapshot.models[0].readings.map(\.average) == [100, 60])

    let suiteName = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = MonitorStore(defaults: defaults, historyURL: nil, claudeReader: reader)
    let watch = try #require(store.headline)
    let pin = LocalRequestThroughput.Pin(source: .claudeCode, modelID: "claude-opus-5-5", tier: .fast)
    store.localHeadline = pin
    #expect(!store.isHeadline(watch))
    await store.refreshLocal(.claudeCode)
    #expect(store.localReading(for: pin)?.average == 100)

    let restored = MonitorStore(defaults: defaults, historyURL: nil)
    #expect(restored.localHeadline == pin)
    restored.headlineID = watch.id
    #expect(restored.localHeadline == nil)
    #expect(restored.isHeadline(watch))

    let later = try #require(await reader.snapshot(now: base.addingTimeInterval(3605)))
    #expect(later.models[0].readings.map(\.tier) == [.fast])
}
