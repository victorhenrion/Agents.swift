import Foundation
import KarrotCodableKit
import MemberwiseInit

@MemberwiseInit(.public)
public struct ChatMessage: Codable, Identifiable {
    public let id: String  //                               id: string
    public let createdAt: Date?  //                         createdAt?: Date
    //public let content: String
    public let experimental_attachments: [Attachment]?  //  experimental_attachments?: Attachment[]
    public let role: Role  //                               role: 'system' | 'user' | 'assistant' | 'data'
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
        case data
    }

    @PolymorphicEnumCodable(identifierCodingKey: "type")
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
