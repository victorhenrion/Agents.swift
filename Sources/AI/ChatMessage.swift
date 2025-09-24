import Foundation
import KarrotCodableKit
import MemberwiseInit

@MemberwiseInit(.public)
public struct ChatMessage: Codable, Identifiable {
    public let id: String  //                               id: string
    public let createdAt: Date?  //                         createdAt?: Date
    public let role: Role  //                               role: 'system' | 'user' | 'assistant'
    public let annotations: [AnyCodable]?  //               annotations?: JSONValue[] | undefined
    public let parts: [Part]  //                            parts?: Array<TextUIPart | ReasoningUIPart | ToolInvocationUIPart | SourceUIPart | FileUIPart | StepStartUIPart>;

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public enum Part {
        case text(ChatMessage.TextPart)
        case reasoning(ChatMessage.ReasoningPart)
        case tool(ChatMessage.ToolPart)
        case sourceURL(ChatMessage.SourceURLPart)
        case sourceDocument(ChatMessage.SourceDocumentPart)
        case file(ChatMessage.FilePart)
        case data(ChatMessage.DataPart)
        case stepStart(ChatMessage.StepStartPart)
    }

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
    }

    //@PolymorphicEnumCodable(identifierCodingKey: "state")
    public enum ToolPart {
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

            public var input: AnyCodable?
        }

        @PolymorphicCodable(identifier: "input-available") @MemberwiseInit(.public)
        public struct InputAvailableState {
            public let type: String  // tool-{name} or dynamic-tool
            public let state = "input-available"
            public let toolCallId: String
            public let providerExecuted: Bool?

            public let input: AnyCodable
            public let callProviderMetadata: ProviderMetadata?
        }

        @PolymorphicCodable(identifier: "output-available") @MemberwiseInit(.public)
        public struct OutputAvailableState {
            public let type: String  // tool-{name} or dynamic-tool
            public let state = "output-available"
            public let toolCallId: String
            public let providerExecuted: Bool?

            public let input: AnyCodable
            public let callProviderMetadata: ProviderMetadata?
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
            public let callProviderMetadata: ProviderMetadata?
            public let rawInput: AnyCodable?
            public let errorText: String
        }
    }

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

    @MemberwiseInit(.public)
    public struct DataPart: Codable {
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

extension ChatMessage.Part: Codable {
    enum PolymorphicMetaCodingKey: CodingKey {
        case `type`
    }

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
        default:
            if type.hasPrefix("tool-") || type == "dynamic-tool" {
                self = .tool(try ChatMessage.ToolPart(from: decoder))
            } else if type.hasPrefix("data-") {
                self = .data(try ChatMessage.DataPart(from: decoder))
            } else {
                throw PolymorphicCodableError.unableToFindPolymorphicType(type)
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let value):
            try value.encode(to: encoder)
        case .reasoning(let value):
            try value.encode(to: encoder)
        case .tool(let value):
            try value.encode(to: encoder)
        case .sourceURL(let value):
            try value.encode(to: encoder)
        case .sourceDocument(let value):
            try value.encode(to: encoder)
        case .file(let value):
            try value.encode(to: encoder)
        case .data(let value):
            try value.encode(to: encoder)
        case .stepStart(let value):
            try value.encode(to: encoder)
        }
    }
}

extension ChatMessage.ToolPart: Codable {
    enum PolymorphicMetaCodingKey: CodingKey {
        case `state`
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PolymorphicMetaCodingKey.self)
        let type = try container.decode(String.self, forKey: PolymorphicMetaCodingKey.state)

        switch type {
        case InputStreamingState.polymorphicIdentifier:
            self = .inputStreaming(try InputStreamingState(from: decoder))
        case InputAvailableState.polymorphicIdentifier:
            self = .inputAvailable(try InputAvailableState(from: decoder))
        case OutputAvailableState.polymorphicIdentifier:
            self = .outputAvailable(try OutputAvailableState(from: decoder))
        case OutputErrorState.polymorphicIdentifier:
            self = .outputError(try OutputErrorState(from: decoder))
        default:
            throw PolymorphicCodableError.unableToFindPolymorphicType(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .inputStreaming(let value):
            try value.encode(to: encoder)
        case .inputAvailable(let value):
            try value.encode(to: encoder)
        case .outputAvailable(let value):
            try value.encode(to: encoder)
        case .outputError(let value):
            try value.encode(to: encoder)
        }
    }
}
