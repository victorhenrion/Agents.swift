import Foundation
import KarrotCodableKit

enum ChatMessageStreamFrame {
    case start(StartFrame)  // "f:{...}"
    case text(String)  // "0:\"...\""
    case reasoning(ReasoningFrame)  // "g:..." or "i:{...}"
    case source(ChatMessage.Source)  // "h:{...}"
    case toolCallStart(ToolCallStartFrame)  // "b:{...}"
    case toolCallDelta(ToolCallDeltaFrame)  // "c:{...}"
    case toolCall(ToolCallFrame)  // "9:{...}"
    case toolResult(ToolResultFrame)  // "a:{...}"
    case finish(FinishFrame)  // "e:{...}"
    case dataDone(DataDoneFrame)  // "d:{...}"
    case error(String)  // "3:..."
    case unknown(String)  // client-only

    struct StartFrame: Codable {
        let messageId: String?
        let createdAt: Date?
    }

    struct ReasoningFrame: Codable {
        let text: String
    }

    struct ToolCallStartFrame: Codable {
        let toolCallId: String
        let toolName: String?
        let args: AnyCodable?
    }

    struct ToolCallDeltaFrame: Codable {
        let toolCallId: String
        let argsDelta: AnyCodable?
    }

    struct ToolCallFrame: Codable {
        let toolCallId: String
        let toolName: String
        let args: AnyCodable
    }

    struct ToolResultFrame: Codable {
        let toolCallId: String
        let result: AnyCodable
    }

    struct FinishFrame: Codable {
        let finishReason: String?
        let isContinued: Bool?
        let usage: Usage?

        struct Usage: Codable {
            let promptTokens: Int?
            let completionTokens: Int?
        }
    }

    struct DataDoneFrame: Codable {
        let finishReason: String?
        let usage: FinishFrame.Usage?
    }

    static func parseAll(from raw: String) -> [ChatMessageStreamFrame] {
        if raw.isEmpty { return [] }
        return raw.split(separator: "\n").compactMap {
            let line = String($0)
            return parseLine(line) ?? .unknown(line)
        }
    }

    private static func parseLine(_ raw: String) -> ChatMessageStreamFrame? {
        guard let sepIndex = raw.firstIndex(of: ":") else { return nil }
        let prefix = String(raw[..<sepIndex])
        var content = String(raw[raw.index(after: sepIndex)...])
        if content.hasSuffix("\n") { content.removeLast() }

        func decode<T: Decodable>(_ type: T.Type) -> T? {
            guard let data = content.data(using: .utf8) else { return nil }
            return try? jsonDecoder.decode(T.self, from: data)
        }

        switch prefix {
        case "f": return decode(StartFrame.self).map { .start($0) }
        case "0": return decode(String.self).map { .text($0) }
        case "g", "i": return parseReasoning(from: content)
        case "h": return decode(ChatMessage.Source.self).map { .source($0) }
        case "b": return decode(ToolCallStartFrame.self).map { .toolCallStart($0) }
        case "c": return decode(ToolCallDeltaFrame.self).map { .toolCallDelta($0) }
        case "9": return decode(ToolCallFrame.self).map { .toolCall($0) }
        case "a": return decode(ToolResultFrame.self).map { .toolResult($0) }
        case "e": return decode(FinishFrame.self).map { .finish($0) }
        case "d": return decode(DataDoneFrame.self).map { .dataDone($0) }
        case "3": return parseError(from: content)
        default: return nil
        }
    }

    private static func parseReasoning(from content: String) -> ChatMessageStreamFrame? {
        if let data = content.data(using: .utf8) {
            if let s = try? jsonDecoder.decode(String.self, from: data) {
                return .reasoning(ReasoningFrame(text: s))
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let txt = (obj["reasoning"] as? String) ?? (obj["data"] as? String)
            {
                return .reasoning(ReasoningFrame(text: txt))
            }
        }
        return nil
    }

    private static func parseError(from content: String) -> ChatMessageStreamFrame? {
        if let data = content.data(using: .utf8) {
            if let s = try? jsonDecoder.decode(String.self, from: data) { return .error(s) }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let msg = (obj["message"] as? String) ?? (obj["error"] as? String)
            {
                return .error(msg)
            }
        }
        return nil
    }
}
