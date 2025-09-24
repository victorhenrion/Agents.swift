import Foundation
import KarrotCodableKit
import MemberwiseInit

@MemberwiseInit(.public)
public struct ChatMessage: Codable, Identifiable {
    public let id: String
    public let role: Role
    public let metadata: AnyCodable?

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public typealias Part = MessagePart

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

    @PolymorphicCodable(identifier: "tool") @MemberwiseInit(.public)
    public struct ToolPart {
        public let type = "tool"
        public let toolName: String
        public let toolCallId: String
        public let dynamic: Bool
        public let providerExecuted: Bool?
        public var input: AnyCodable?
        public var callProviderMetadata: ProviderMetadata?
        public var state: State

        public typealias State = ToolState
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

    @PolymorphicCodable(identifier: "data") @MemberwiseInit(.public)
    public struct DataPart: Codable {
        public let type = "data"
        public let dataType: String
        public let id: String?
        public let data: AnyCodable?
    }

    @PolymorphicCodable(identifier: "step-start") @MemberwiseInit(.public)
    public struct StepStartPart {
        public let type = "step-start"
    }

    public typealias ProviderMetadata = [String: [String: AnyCodable]]
}

@PolymorphicEnumCodable(identifierCodingKey: "type")
public enum MessagePart {
    case text(ChatMessage.TextPart)
    case reasoning(ChatMessage.ReasoningPart)
    case tool(ChatMessage.ToolPart)
    case sourceURL(ChatMessage.SourceURLPart)
    case sourceDocument(ChatMessage.SourceDocumentPart)
    case file(ChatMessage.FilePart)
    case data(ChatMessage.DataPart)
    case stepStart(ChatMessage.StepStartPart)
}

@PolymorphicEnumCodable(identifierCodingKey: "name")
public enum ToolState {
    case inputStreaming(InputStreamingState)
    case inputAvailable(InputAvailableState)
    case outputAvailable(OutputAvailableState)
    case outputError(OutputErrorState)

    @PolymorphicCodable(identifier: "input-streaming") @MemberwiseInit(.public)
    public struct InputStreamingState {
        public let name = "input-streaming"
    }

    @PolymorphicCodable(identifier: "input-available") @MemberwiseInit(.public)
    public struct InputAvailableState {
        public let name = "input-available"
    }

    @PolymorphicCodable(identifier: "output-available") @MemberwiseInit(.public)
    public struct OutputAvailableState {
        public let name = "output-available"
        public let output: AnyCodable?
        public let preliminary: Bool?
    }

    @PolymorphicCodable(identifier: "output-error") @MemberwiseInit(.public)
    public struct OutputErrorState {
        public let name = "output-error"
        public let rawInput: AnyCodable?
        public let errorText: String
    }
}
