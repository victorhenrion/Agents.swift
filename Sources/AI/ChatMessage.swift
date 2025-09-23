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

    //@PolymorphicEnumCodable(identifierCodingKey: "type")
    public enum Part {
        case text(ChatMessage.TextPart)
        case reasoning(ChatMessage.ReasoningPart)
        case toolInvocation(ChatMessage.ToolInvocationPart)
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
        public let reasoning: String
    }

    @PolymorphicCodable(identifier: "tool-invocation") @MemberwiseInit(.public)
    public struct ToolInvocationPart {
        public let type = "tool-invocation"
        public let toolInvocation: ToolInvocation
    }

    @MemberwiseInit(.public)
    public struct ToolInvocation: Codable {
        public let state: State
        public let toolCallId: String
        public let toolName: String
        public let args: AnyCodable?  // can be anything (not just array or object)
        public let result: AnyCodable?  // can be anything
        public let step: Int?

        public enum State: String, Codable {
            case partialCall
            case call
            case result
        }
    }

    @PolymorphicCodable(identifier: "source") @MemberwiseInit(.public)
    public struct SourcePart {
        public let type = "source"
        public let source: Source
    }

    @MemberwiseInit(.public)
    public struct Source: Codable {
        public let sourceType: String
        public let id: String
        public let url: String
        public let title: String?
        public let providerMetadata: [String: [String: AnyCodable]]?
    }

    @PolymorphicCodable(identifier: "file") @MemberwiseInit(.public)
    public struct FilePart {
        public let type = "file"
        public let mimeType: String
        public let data: String
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
        case ChatMessage.ToolInvocationPart.polymorphicIdentifier:
            self = .toolInvocation(try ChatMessage.ToolInvocationPart(from: decoder))
        case ChatMessage.SourcePart.polymorphicIdentifier:
            self = .source(try ChatMessage.SourcePart(from: decoder))
        case ChatMessage.FilePart.polymorphicIdentifier:
            self = .file(try ChatMessage.FilePart(from: decoder))
        case ChatMessage.StepStartPart.polymorphicIdentifier:
            self = .stepStart(try ChatMessage.StepStartPart(from: decoder))
        default:
            throw PolymorphicCodableError.unableToFindPolymorphicType(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let value):
            try value.encode(to: encoder)
        case .reasoning(let value):
            try value.encode(to: encoder)
        case .toolInvocation(let value):
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
