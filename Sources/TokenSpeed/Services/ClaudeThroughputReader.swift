import Foundation

actor ClaudeThroughputReader {
    private struct Record: Decodable {
        struct Parameters: Decodable {
            let speed: String?
        }

        struct Message: Decodable {
            struct Usage: Decodable {
                let output_tokens: Int?
                let speed: String?
            }

            let id: String?
            let model: String?
            let stop_reason: String?
            let usage: Usage?
        }

        let type: String
        let timestamp: String?
        let id: String?
        let requestRef: String?
        let requestId: String?
        let params: Parameters?
        let message: Message?
    }

    private struct RequestStart: Equatable {
        let date: Date
        let speed: String?
    }

    private struct Response {
        let messageID: String
        let requestID: String?
        let model: String
        let date: Date
        let outputTokens: Int?
        let speed: String?

        var identity: String { requestID ?? messageID }
    }

    private struct Sample {
        let id: String
        let request: LocalRequestThroughput.Request
    }

    private struct CachedFile {
        let modifiedAt: Date
        let samples: [Sample]
    }

    private let projects: URL
    private var cache: [URL: CachedFile] = [:]

    init(home: URL = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].flatMap {
        $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)) {
        projects = home.appendingPathComponent("projects", isDirectory: true)
    }

    func snapshot(now: Date = .now) -> LocalRequestThroughput? {
        let cutoff = now.addingTimeInterval(-LocalRequestThroughput.window)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard FileManager.default.isReadableFile(atPath: projects.path),
              let files = FileManager.default.enumerator(
                at: projects, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
              ) else { return nil }

        var recent: [URL: CachedFile] = [:]
        var unique: [String: LocalRequestThroughput.Request] = [:]
        for case let file as URL in files {
            if Task.isCancelled { return nil }
            guard file.pathExtension == "jsonl",
                  let properties = try? file.resourceValues(forKeys: keys), properties.isRegularFile == true,
                  let modified = properties.contentModificationDate, modified >= cutoff else { continue }
            let samples: [Sample]
            if let cached = cache[file], cached.modifiedAt == modified {
                samples = cached.samples
            } else {
                guard let read = read(file, since: cutoff) else { continue }
                samples = read
            }
            recent[file] = CachedFile(modifiedAt: modified, samples: samples)
            for sample in samples {
                if let existing = unique[sample.id], existing.startedAt <= sample.request.startedAt { continue }
                unique[sample.id] = sample.request
            }
        }
        cache = recent
        return LocalRequestThroughput(requests: Array(unique.values), now: now)
    }

    private func read(_ file: URL, since cutoff: Date) -> [Sample]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let startMarker = Data(#""type":"api-request""#.utf8)
        let responseMarker = Data(#""requestRef":"#.utf8)
        let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let decoder = JSONDecoder()
        var starts: [String: RequestStart] = [:]
        var responses: [String: Response] = [:]
        var ambiguous: Set<String> = []

        for line in data.split(separator: 10) {
            guard line.range(of: startMarker) != nil || line.range(of: responseMarker) != nil,
                  let record = try? decoder.decode(Record.self, from: line),
                  let timestamp = record.timestamp,
                  let date = (try? timestampStyle.parse(timestamp)) ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
            else { continue }

            switch record.type {
            case "api-request":
                guard let ref = record.id else { continue }
                let start = RequestStart(date: date, speed: record.params?.speed)
                if let existing = starts[ref], existing != start { ambiguous.insert(ref) }
                starts[ref] = start
            case "assistant":
                guard date >= cutoff, let ref = record.requestRef, let message = record.message,
                      let id = message.id, let model = message.model, message.stop_reason != nil else { continue }
                let response = Response(
                    messageID: id, requestID: record.requestId, model: model, date: date,
                    outputTokens: message.usage?.output_tokens, speed: message.usage?.speed
                )
                if let existing = responses[ref] {
                    guard existing.messageID == id, existing.model == model,
                          existing.requestID == nil || response.requestID == nil
                            || existing.requestID == response.requestID else {
                        ambiguous.insert(ref)
                        continue
                    }
                    if date < existing.date { continue }
                }
                responses[ref] = response
            default:
                break
            }
        }

        // The request reference stays the same across the thinking, text and tool-use blocks.
        // Use the last completed block's cumulative usage once for the whole request.
        return responses.compactMap { ref, response in
            guard !ambiguous.contains(ref), let start = starts[ref], response.date > start.date else { return nil }
            let seconds = response.date.timeIntervalSince(start.date)
            let reading = response.outputTokens.flatMap { tokens in
                tokens > 0 ? ThroughputPoint(date: response.date, tps: Double(tokens) / seconds) : nil
            }
            let request = LocalRequestThroughput.Request(
                model: response.model, tier: .init(response.speed ?? start.speed), startedAt: start.date,
                completedAt: response.date, reading: reading
            )
            return Sample(id: response.identity, request: request)
        }
    }
}
