import Foundation
import ISO8601JSON
import KarrotCodableKit

@PolymorphicEnumCodable(identifierCodingKey: "type", fallbackCaseName: "data")
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

    @PolymorphicCodable(identifier: "text-start")
    package struct TextStart {
        let type = "text-start"
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "text-delta")
    package struct TextDelta {
        let type = "text-delta"
        let delta: String
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "text-end")
    package struct TextEnd {
        let type = "text-end"
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "reasoning-start")
    package struct ReasoningStart {
        let type = "reasoning-start"
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "reasoning-delta")
    package struct ReasoningDelta {
        let type = "reasoning-delta"
        let id: String
        let delta: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "reasoning-end")
    package struct ReasoningEnd {
        let type = "reasoning-end"
        let id: String
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "error")
    package struct Error {
        let type = "error"
        let errorText: String
    }

    @PolymorphicCodable(identifier: "tool-input-available")
    package struct ToolInputAvailable {
        let type = "tool-input-available"
        let toolCallId: String
        let toolName: String
        let input: AnyCodable
        let providerExecuted: Bool?
        let providerMetadata: ProviderMetadata?
        let dynamic: Bool?
    }

    @PolymorphicCodable(identifier: "tool-input-error")
    package struct ToolInputError {
        let type = "tool-input-error"
        let toolCallId: String
        let toolName: String
        let input: AnyCodable?
        let providerExecuted: Bool?
        let providerMetadata: ProviderMetadata?
        let dynamic: Bool?
        let errorText: String
    }

    @PolymorphicCodable(identifier: "tool-output-available")
    package struct ToolOutputAvailable {
        let type = "tool-output-available"
        let toolCallId: String
        let output: AnyCodable
        let providerExecuted: Bool?
        let dynamic: Bool?
        let preliminary: Bool?
    }

    @PolymorphicCodable(identifier: "tool-output-error")
    package struct ToolOutputError {
        let type = "tool-output-error"
        let toolCallId: String
        let errorText: String
        let providerExecuted: Bool?
        let dynamic: Bool?
    }

    @PolymorphicCodable(identifier: "tool-input-start")
    package struct ToolInputStart {
        let type = "tool-input-start"
        let toolCallId: String
        let toolName: String
        let providerExecuted: Bool?
        let dynamic: Bool?
    }

    @PolymorphicCodable(identifier: "tool-input-delta")
    package struct ToolInputDelta {
        let type = "tool-input-delta"
        let toolCallId: String
        let inputTextDelta: String
    }

    @PolymorphicCodable(identifier: "source-url")
    package struct SourceURL {
        let type = "source-url"
        let sourceId: String
        let url: String
        let title: String?
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "source-document")
    package struct SourceDocument {
        let type = "source-document"
        let sourceId: String
        let mediatype: String
        let title: String
        let filename: String?
        let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "file")
    package struct File {
        let type = "file"
        let url: String
        let mediatype: String
    }

    // this is our fallback type, if chunk doesn't conform to it, it will throw (good)
    package struct Data: Codable {
        let type: String  // "data-{name}"
        let id: String?
        let data: AnyCodable
        let transient: Bool?
    }

    @PolymorphicCodable(identifier: "start-step")
    package struct StartStep {
        let type = "start-step"
    }

    @PolymorphicCodable(identifier: "finish-step")
    package struct FinishStep {
        let type = "finish-step"
    }

    @PolymorphicCodable(identifier: "start")
    package struct Start {
        let type = "start"
        let messageId: String?
        let messageMetadata: AnyCodable?
    }

    @PolymorphicCodable(identifier: "finish")
    package struct Finish {
        let type = "finish"
        let messageMetadata: AnyCodable?
    }

    @PolymorphicCodable(identifier: "abort")
    package struct Abort {
        let type = "abort"
    }

    @PolymorphicCodable(identifier: "message-metadata")
    package struct MessageMetadata {
        let type = "message-metadata"
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
                print("Failed to parse chunk: \(line)")
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
