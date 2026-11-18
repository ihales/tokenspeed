import Foundation

struct CodexRollouts {
    typealias Turn = CodexThroughputReader.Turn

    struct Completion {
        let date: Date
        let responseID: String
        let outputTokens: Int
    }

    struct History {
        var completions: [Turn: [Completion]] = [:]
        var interruptions: [Turn: [Date]] = [:]
        var compactions: Set<String> = []
    }

    private struct Record: Decodable {
        struct Payload: Decodable {
            struct Usage: Decodable {
                let output_tokens: Int
            }

            struct ItemMetadata: Decodable {
                let turn_id: String?
            }

            let response_id: String?
            let thread_id: UUID?
            let turn_id: String?
            let usage: Usage?
            let type: String?
            let internal_chat_message_metadata_passthrough: ItemMetadata?
            let compaction_response_id: String?

            var toolResultTurnID: String? {
                guard type?.hasSuffix("_output") == true else { return nil }
                return internal_chat_message_metadata_passthrough?.turn_id
            }
        }

        let type: String
        let payload: Payload
    }

    func read(home: URL, threads: Set<UUID>, since cutoff: Date) -> History {
        var history = History()
        var responseIDs: Set<String> = []
        for (threadID, file) in files(home: home, threads: threads) {
            readTail(file, since: cutoff) { date, record in
                let payload = record.payload
                switch record.type {
                case "token_usage_record":
                    guard payload.thread_id == threadID, let turnID = payload.turn_id,
                          let id = payload.response_id, let usage = payload.usage,
                          responseIDs.insert(id).inserted else { return }
                    let turn = Turn(threadID: threadID, turnID: turnID)
                    history.completions[turn, default: []].append(
                        Completion(date: date, responseID: id, outputTokens: usage.output_tokens)
                    )
                case "response_item":
                    guard let turnID = payload.toolResultTurnID else { return }
                    let turn = Turn(threadID: threadID, turnID: turnID)
                    history.interruptions[turn, default: []].append(date)
                case "event_msg":
                    guard payload.type == "stream_error", let turnID = payload.turn_id else { return }
                    let turn = Turn(threadID: threadID, turnID: turnID)
                    history.interruptions[turn, default: []].append(date)
                case "compacted":
                    if let id = payload.compaction_response_id { history.compactions.insert(id) }
                default:
                    break
                }
            }
        }
        return history
    }

    private func files(home: URL, threads: Set<UUID>) -> [UUID: URL] {
        var remaining = threads
        var files: [UUID: URL] = [:]
        for directory in ["sessions", "archived_sessions"] {
            guard !remaining.isEmpty,
                  let urls = FileManager.default.enumerator(
                    at: home.appendingPathComponent(directory, isDirectory: true),
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                  ) else { continue }
            for case let url as URL in urls {
                guard url.pathExtension == "jsonl",
                      let id = UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.suffix(36))),
                      remaining.remove(id) != nil else { continue }
                files[id] = url
                if remaining.isEmpty { break }
            }
        }
        return files
    }

    /// Rolls append in timestamp order. Read backwards to avoid scanning the full transcript on refresh.
    private func readTail(_ url: URL, since cutoff: Date, visit: (Date, Record) -> Void) {
        guard let file = try? FileHandle(forReadingFrom: url),
              var offset = try? file.seekToEnd() else { return }
        defer { try? file.close() }
        let timestampPrefix = Data("{\"timestamp\":\"".utf8)
        let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let candidates = ["token_usage_record", "compacted", "stream_error"].map { Data("\"type\":\"\($0)\"".utf8) }
        let toolOutput = Data("_output\"".utf8)
        let decoder = JSONDecoder()

        func visitLine(_ line: Data) -> Bool {
            guard line.starts(with: timestampPrefix),
                  let closingQuote = line.dropFirst(timestampPrefix.count).prefix(40).firstIndex(of: 34),
                  let timestamp = String(data: line.dropFirst(timestampPrefix.count).prefix(upTo: closingQuote), encoding: .utf8),
                  let date = try? timestampStyle.parse(timestamp) else { return true }
            guard date >= cutoff else { return false }
            let header = line.prefix(256)
            if (header.range(of: toolOutput) != nil || candidates.contains(where: { header.range(of: $0) != nil })),
               let record = try? decoder.decode(Record.self, from: line) {
                visit(date, record)
            }
            return true
        }

        var carry = Data()
        while offset > 0 {
            let count = min(offset, 256 * 1024)
            offset -= count
            guard (try? file.seek(toOffset: offset)) != nil,
                  var block = try? file.read(upToCount: Int(count)),
                  !block.isEmpty else { return }
            block.append(carry)
            var end = block.endIndex
            while let newline = block[..<end].lastIndex(of: 10) {
                if !visitLine(block[(newline + 1)..<end]) { return }
                end = newline
            }
            carry = block[..<end]
        }
        _ = visitLine(carry)
    }
}
