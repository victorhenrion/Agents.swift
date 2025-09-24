import Foundation
import ISO8601JSON
import KarrotCodableKit

@PolymorphicEnumDecodable(identifierCodingKey: "type", fallbackCaseName: "data")
package enum ChatMessageChunk {
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
    package struct TextStart {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "text-delta")
    package struct TextDelta {
        let delta: String
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "text-end")
    package struct TextEnd {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "reasoning-start")
    package struct ReasoningStart {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "reasoning-delta")
    package struct ReasoningDelta {
        let id: String
        let delta: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "reasoning-end")
    package struct ReasoningEnd {
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "error")
    package struct Error {
        let errorText: String
    }

    @PolymorphicDecodable(identifier: "tool-input-available")
    package struct ToolInputAvailable {
        let toolCallId: String
        let toolName: String
        let input: AnyCodable
        let providerExecuted: Bool?
        let providerMetadata: ProviderMetadata?
        let dynamic: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-input-error")
    package struct ToolInputError {
        let toolCallId: String
        let toolName: String
        let input: AnyCodable?
        let providerExecuted: Bool?
        let providerMetadata: ProviderMetadata?
        let dynamic: Bool?
        let errorText: String
    }

    @PolymorphicDecodable(identifier: "tool-output-available")
    package struct ToolOutputAvailable {
        let toolCallId: String
        let output: AnyCodable
        let providerExecuted: Bool?
        let dynamic: Bool?
        let preliminary: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-output-error")
    package struct ToolOutputError {
        let toolCallId: String
        let errorText: String
        let providerExecuted: Bool?
        let dynamic: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-input-start")
    package struct ToolInputStart {
        let toolCallId: String
        let toolName: String
        let providerExecuted: Bool?
        let dynamic: Bool?
    }

    @PolymorphicDecodable(identifier: "tool-input-delta")
    package struct ToolInputDelta {
        let toolCallId: String
        let inputTextDelta: String
    }

    @PolymorphicDecodable(identifier: "source-url")
    package struct SourceURL {
        let sourceId: String
        let url: String
        let title: String?
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "source-document")
    package struct SourceDocument {
        let sourceId: String
        let mediatype: String
        let title: String
        let filename: String?
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicDecodable(identifier: "file")
    package struct File {
        let url: String
        let mediatype: String
    }

    // this is our fallback type, if chunk doesn't conform to it, it will throw (good)
    @PolymorphicDecodable(identifier: "data")  // ->>> this is required but then I think we loose or custom type, which is an issue in the builder (TODO: check this)
    package struct Data {
        let type: String  // "data-{name}"
        let id: String?
        let data: AnyCodable
        let transient: Bool?
    }

    @PolymorphicDecodable(identifier: "start-step")
    package struct StartStep {
    }

    @PolymorphicDecodable(identifier: "finish-step")
    package struct FinishStep {
    }

    @PolymorphicDecodable(identifier: "start")
    package struct Start {
        let messageId: String?
        let messageMetadata: AnyCodable?
    }

    @PolymorphicDecodable(identifier: "finish")
    package struct Finish {
        let messageMetadata: AnyCodable?
    }

    @PolymorphicDecodable(identifier: "abort")
    package struct Abort {
    }

    @PolymorphicDecodable(identifier: "message-metadata")
    package struct MessageMetadata {
        let messageMetadata: AnyCodable
    }

    package typealias ProviderMetadata = [String: [String: AnyCodable]]
}

extension ChatMessageChunk {
    package static func parseAll(from raw: String) -> [ChatMessageChunk] {
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
