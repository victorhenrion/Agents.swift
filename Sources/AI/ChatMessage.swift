import Foundation
import KarrotCodableKit
import MemberwiseInit

@MemberwiseInit(.public)
public struct ChatMessage: Codable, Identifiable {
    public let id: String
    public let role: Role
    public let metadata: AnyCodable?
    public let parts: [Part]

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public typealias Part = ChatMessagePart

    @PolymorphicCodable(identifier: "text") @MemberwiseInit(.public)
    public struct TextPart {
        public let type = "text"
        public var text: String
        public var state: State?
        public var providerMetadata: ProviderMetadata?

        public enum State: String, Codable {
            case streaming
            case done
        }

        public init(text: String) {
            self.init(text: text, state: .done, providerMetadata: nil)
        }
    }

    @PolymorphicCodable(identifier: "reasoning") @MemberwiseInit(.public)
    public struct ReasoningPart {
        public let type = "reasoning"
        public var text: String
        public var state: State?
        public var providerMetadata: ProviderMetadata?

        public enum State: String, Codable {
            case streaming
            case done
        }

        public init(text: String) {
            self.init(text: text, state: .done, providerMetadata: nil)
        }
    }

    public typealias ToolPart = ChatMessageToolPart

    @PolymorphicCodable(identifier: "source-url") @MemberwiseInit(.public)
    public struct SourceURLPart {
        public let type = "source-url"
        public let sourceId: String
        public let url: String
        public let title: String?
        public let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "source-document") @MemberwiseInit(.public)
    public struct SourceDocumentPart {
        public let type = "source-document"
        public let sourceId: String
        public let mediaType: String
        public let title: String
        public let filename: String?
        public let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "file") @MemberwiseInit(.public)
    public struct FilePart {
        public let type = "file"
        public let mediaType: String
        public let filename: String?
        public let url: String
        public let providerMetadata: ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "data") @MemberwiseInit(.public)
    public struct DataPart {
        public let type: String  // data-{name}
        public let id: String?
        public let data: AnyCodable?
    }

    @PolymorphicCodable(identifier: "step-start") @MemberwiseInit(.public)
    public struct StepStartPart {
        public let type = "step-start"
    }

    public typealias ProviderMetadata = [String: [String: AnyCodable]]
}

@PolymorphicEnumEncodable(identifierCodingKey: "type")  // EnumEncodable only, decode is custom
public enum ChatMessagePart: Decodable {
    case text(ChatMessage.TextPart)
    case reasoning(ChatMessage.ReasoningPart)
    case sourceURL(ChatMessage.SourceURLPart)
    case sourceDocument(ChatMessage.SourceDocumentPart)
    case file(ChatMessage.FilePart)
    case stepStart(ChatMessage.StepStartPart)
    case tool(ChatMessage.ToolPart)
    case data(ChatMessage.DataPart)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PolymorphicMetaCodingKey.self)
        let type = try container.decode(String.self, forKey: PolymorphicMetaCodingKey.type)

        switch type {
        case ChatMessage.TextPart.polymorphicIdentifier:
            self = .text(try ChatMessage.TextPart(from: decoder))
        case ChatMessage.ReasoningPart.polymorphicIdentifier:
            self = .reasoning(try ChatMessage.ReasoningPart(from: decoder))
        case ChatMessage.SourceURLPart.polymorphicIdentifier:
            self = .sourceURL(try ChatMessage.SourceURLPart(from: decoder))
        case ChatMessage.SourceDocumentPart.polymorphicIdentifier:
            self = .sourceDocument(try ChatMessage.SourceDocumentPart(from: decoder))
        case ChatMessage.FilePart.polymorphicIdentifier:
            self = .file(try ChatMessage.FilePart(from: decoder))
        case ChatMessage.StepStartPart.polymorphicIdentifier:
            self = .stepStart(try ChatMessage.StepStartPart(from: decoder))
        case "dynamic-tool":
            self = .tool(try ChatMessage.ToolPart(from: decoder))
        case type where type.hasPrefix("tool-"):
            self = .tool(try ChatMessage.ToolPart(from: decoder))
        case type where type.hasPrefix("data-"):
            self = .data(try ChatMessage.DataPart(from: decoder))
        default:
            throw PolymorphicCodableError.unableToFindPolymorphicType(type)
        }
    }

    enum PolymorphicMetaCodingKey: CodingKey {
        case `type`
    }
}

@PolymorphicCodable(identifier: "tool") @PolymorphicEnumCodable(identifierCodingKey: "state")
public enum ChatMessageToolPart {
    case inputStreaming(InputStreamingState)
    case inputAvailable(InputAvailableState)
    case outputAvailable(OutputAvailableState)
    case outputError(OutputErrorState)

    @PolymorphicCodable(identifier: "input-streaming") @MemberwiseInit(.public)
    public struct InputStreamingState {
        public let type: String  // tool-{name} or dynamic-tool
        public let state = "input-streaming"
        public let toolCallId: String
        public let providerExecuted: Bool?

        public let input: AnyCodable?
    }

    @PolymorphicCodable(identifier: "input-available") @MemberwiseInit(.public)
    public struct InputAvailableState {
        public let type: String  // tool-{name} or dynamic-tool
        public let state = "input-available"
        public let toolCallId: String
        public let providerExecuted: Bool?

        public let input: AnyCodable
        public let callProviderMetadata: ChatMessage.ProviderMetadata?
    }

    @PolymorphicCodable(identifier: "output-available") @MemberwiseInit(.public)
    public struct OutputAvailableState {
        public let type: String  // tool-{name} or dynamic-tool
        public let state = "output-available"
        public let toolCallId: String
        public let providerExecuted: Bool?

        public let input: AnyCodable
        public let callProviderMetadata: ChatMessage.ProviderMetadata?
        public let output: AnyCodable?
        public let preliminary: Bool?
    }

    @PolymorphicCodable(identifier: "output-error") @MemberwiseInit(.public)
    public struct OutputErrorState {
        public let type: String  // tool-{name} or dynamic-tool
        public let state = "output-error"
        public let toolCallId: String
        public let providerExecuted: Bool?

        public let input: AnyCodable?
        public let callProviderMetadata: ChatMessage.ProviderMetadata?
        public let rawInput: AnyCodable?
        public let errorText: String
    }
}
