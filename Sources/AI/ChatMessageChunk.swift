import Foundation
import ISO8601JSON
import KarrotCodableKit

@PolymorphicEnumDecodable(identifierCodingKey: "type", fallbackCaseName: "data")
public enum ChatMessageChunk: Hashable {
    case textStart(TextStart)
    case textDelta(TextDelta)
    case textEnd(TextEnd)
    case reasoningStart(ReasoningStart)
    case reasoningDelta(ReasoningDelta)
    case reasoningEnd(ReasoningEnd)
    case error(Error)
    case toolInputAvailable(ToolInputAvailable)
    case toolInputError(ToolInputError)
    case toolOutputAvailable(ToolOutputAvailable)
    case toolOutputError(ToolOutputError)
    case toolInputStart(ToolInputStart)
    case toolInputDelta(ToolInputDelta)
    case sourceURL(SourceURL)
    case sourceDocument(SourceDocument)
    case file(File)
    case data(Data)
    case startStep(StartStep)
    case finishStep(FinishStep)
    case start(Start)
    case finish(Finish)
    case abort(Abort)
    case messageMetadata(MessageMetadata)

    @PolymorphicDecodable(identifier: "text-start")
    public struct TextStart: Hashable {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "text-delta")
    public struct TextDelta: Hashable {
        let delta: String
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "text-end")
    public struct TextEnd: Hashable {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "reasoning-start")
    public struct ReasoningStart: Hashable {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "reasoning-delta")
    public struct ReasoningDelta: Hashable {
        let id: String
        let delta: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "reasoning-end")
    public struct ReasoningEnd: Hashable {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "error")
    public struct Error: Hashable {
        let errorText: String
    }

    @PolymorphicDecodable(identifier: "tool-input-available")
    public struct ToolInputAvailable: Hashable {
        public let toolCallId: String
        public let toolName: String
        public let input: AnyCodable
        public let providerExecuted: Bool?
        public let providerMetadata: ProviderMetadata?
        public let dynamic: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-input-error")
    public struct ToolInputError: Hashable {
        let toolCallId: String
        let toolName: String
        let input: AnyCodable?
        let providerExecuted: Bool?
        let providerMetadata: ProviderMetadata?
        let dynamic: Bool?
        let errorText: String
    }

    @PolymorphicDecodable(identifier: "tool-output-available")
    public struct ToolOutputAvailable: Hashable {
        let toolCallId: String
        let output: AnyCodable
        let providerExecuted: Bool?
        let dynamic: Bool?
        let preliminary: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-output-error")
    public struct ToolOutputError: Hashable {
        let toolCallId: String
        let errorText: String
        let providerExecuted: Bool?
        let dynamic: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-input-start")
    public struct ToolInputStart: Hashable {
        let toolCallId: String
        let toolName: String
        let providerExecuted: Bool?
        let dynamic: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-input-delta")
    public struct ToolInputDelta: Hashable {
        let toolCallId: String
        let inputTextDelta: String
    }

    @PolymorphicDecodable(identifier: "source-url")
    public struct SourceURL: Hashable {
        let sourceId: String
        let url: String
        let title: String?
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "source-document")
    public struct SourceDocument: Hashable {
        let sourceId: String
        let mediatype: String
        let title: String
        let filename: String?
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "file")
    public struct File: Hashable {
        let url: String
        let mediatype: String
    }

    // this is our fallback type, if chunk doesn't conform to it, it will throw (good)
    @PolymorphicDecodable(identifier: "data")  // ->>> this is required but then I think we loose or custom type, which is an issue in the builder (TODO: check this)
    public struct Data: Hashable {
        let type: String  // "data-{name}"
        let id: String?
        let data: AnyCodable
        let transient: Bool?
    }

    @PolymorphicDecodable(identifier: "start-step")
    public struct StartStep: Hashable {
    }

    @PolymorphicDecodable(identifier: "finish-step")
    public struct FinishStep: Hashable {
    }

    @PolymorphicDecodable(identifier: "start")
    public struct Start: Hashable {
        let messageId: String?
        let messageMetadata: AnyCodable?
    }

    @PolymorphicDecodable(identifier: "finish")
    public struct Finish: Hashable {
        let messageMetadata: AnyCodable?
    }

    @PolymorphicDecodable(identifier: "abort")
    public struct Abort: Hashable {
    }

    @PolymorphicDecodable(identifier: "message-metadata")
    public struct MessageMetadata: Hashable {
        let messageMetadata: AnyCodable
    }

    public typealias ProviderMetadata = [String: [String: AnyCodable]]
}

extension ChatMessageChunk {
    public static func parseAll(from raw: String) -> [ChatMessageChunk] {
        var chunks: [ChatMessageChunk] = []
        for line in raw.split(separator: "\n") {
            if let data = String(line).data(using: .utf8),
                let chunk = try? jsonDecoder.decode(ChatMessageChunk.self, from: data)
            {
                chunks.append(chunk)
            } else {
                print("Failed to parse chunk: \"\(line)\"")
            }
        }
        return chunks
    }
}

private let jsonDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
    return dec
}()
