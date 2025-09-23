import Foundation
import KarrotCodableKit
import MemberwiseInit

@MemberwiseInit(.public)
public struct ChatMessage: Codable, Identifiable {
    public let id: String  //                               id: string
    public let createdAt: Date?  //                         createdAt?: Date
    public let experimental_attachments: [Attachment]?  //  experimental_attachments?: Attachment[]
    public let role: Role  //                               role: 'system' | 'user' | 'assistant'
    public let annotations: [AnyCodable]?  //               annotations?: JSONValue[] | undefined
    public let parts: [Part]  //                            parts?: Array<TextUIPart | ReasoningUIPart | ToolInvocationUIPart | SourceUIPart | FileUIPart | StepStartUIPart>;

    @MemberwiseInit(.public)
    public struct Attachment: Codable {
        public let name: String?
        public let contentType: String?
        public let url: String
    }

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public enum Part {
        case text(ChatMessage.TextPart)
        case reasoning(ChatMessage.ReasoningPart)
        case tool(ChatMessage.ToolPart)
        case source(ChatMessage.SourcePart)
        case file(ChatMessage.FilePart)
        case stepStart(ChatMessage.StepStartPart)
    }

    @PolymorphicCodable(identifier: "text") @MemberwiseInit(.public)
    public struct TextPart {
        public let type = "text"
        public let text: String
    }

    @PolymorphicCodable(identifier: "reasoning") @MemberwiseInit(.public)
    public struct ReasoningPart {
        public let type = "reasoning"
        public let text: String
    }

    @PolymorphicEnumCodable(identifierCodingKey: "state")
    public enum ToolPart {
        case inputStreaming(InputStreamingState)
        case inputAvailable(InputAvailableState)
        case outputAvailable(OutputAvailableState)
        case outputError(OutputErrorState)

        @PolymorphicCodable(identifier: "input-streaming") @MemberwiseInit(.public)
        public struct InputStreamingState: Codable {
            public let state = "input-streaming"
            public let toolCallId: String
            public let providerExecuted: Bool?

            public let input: AnyCodable?
        }

        @PolymorphicCodable(identifier: "input-available") @MemberwiseInit(.public)
        public struct InputAvailableState: Codable {
            public let state = "input-available"
            public let toolCallId: String
            public let providerExecuted: Bool?

            public let input: AnyCodable
            public let callProviderMetadata: [String: [String: AnyCodable]]?
        }

        @PolymorphicCodable(identifier: "output-available") @MemberwiseInit(.public)
        public struct OutputAvailableState: Codable {
            public let state = "output-available"
            public let toolCallId: String
            public let providerExecuted: Bool?

            public let input: AnyCodable
            public let callProviderMetadata: [String: [String: AnyCodable]]?
            public let output: AnyCodable?
            public let preliminary: Bool?
        }

        @PolymorphicCodable(identifier: "output-error") @MemberwiseInit(.public)
        public struct OutputErrorState: Codable {
            public let state = "output-error"
            public let toolCallId: String
            public let providerExecuted: Bool?

            public let input: AnyCodable?
            public let callProviderMetadata: [String: [String: AnyCodable]]?
            public let rawInput: AnyCodable?
            public let errorText: String
        }
    }

    @PolymorphicCodable(identifier: "source") @MemberwiseInit(.public)
    public struct SourcePart {
        public let type = "source"
        public let source: Source

        @MemberwiseInit(.public)
        public struct Source: Codable {
            public let sourceType: String
            public let id: String
            public let url: String
            public let title: String?
            public let providerMetadata: [String: [String: AnyCodable]]?
        }
    }

    @PolymorphicCodable(identifier: "file") @MemberwiseInit(.public)
    public struct FilePart {
        public let type = "file"
        public let url: String
    }

    @PolymorphicCodable(identifier: "step-start") @MemberwiseInit(.public)
    public struct StepStartPart {
        public let type = "step-start"
    }
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
        case ChatMessage.SourcePart.polymorphicIdentifier:
            self = .source(try ChatMessage.SourcePart(from: decoder))
        case ChatMessage.FilePart.polymorphicIdentifier:
            self = .file(try ChatMessage.FilePart(from: decoder))
        case ChatMessage.StepStartPart.polymorphicIdentifier:
            self = .stepStart(try ChatMessage.StepStartPart(from: decoder))
        default:
            if type.hasPrefix("tool-") {
                self = .tool(try ChatMessage.ToolPart(from: decoder))
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
        case .source(let value):
            try value.encode(to: encoder)
        case .file(let value):
            try value.encode(to: encoder)
        case .stepStart(let value):
            try value.encode(to: encoder)
        }
    }
}
