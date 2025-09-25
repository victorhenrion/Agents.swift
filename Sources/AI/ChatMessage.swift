import Foundation
import KarrotCodableKit
import MemberwiseInit

@MemberwiseInit(.public)
public struct ChatMessage: Codable, Identifiable {
    public let id: String
    public let role: Role
    public let metadata: AnyCodable?
    public let parts: [Part]

    // user message shorthand
    public init(_ parts: [Part]) {
        self.id = "user_\(UUID().uuidString)"
        self.role = .user
        self.metadata = nil
        self.parts = parts
    }

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

    @PolymorphicCodable(identifier: "dynamic-tool") @MemberwiseInit(.public)
    public struct DynamicToolPart {
        public let type = "dynamic-tool"
        public let toolName: String
        public let toolCallId: String

        public var state: State
        public var providerExecuted: Bool?
        public var input: AnyCodable?
        public var callProviderMetadata: ChatMessage.ProviderMetadata?
        public var output: AnyCodable?
        public var preliminary: Bool?
        public var errorText: String?

        public enum State: String, Codable {
            case inputStreaming = "input-streaming"
            case inputAvailable = "input-available"
            case outputAvailable = "output-available"
            case outputError = "output-error"
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

    @PolymorphicCodable(identifier: "step-start") @MemberwiseInit(.public)
    public struct StepStartPart {
        public let type = "step-start"
    }

    @PolymorphicCodable(identifier: "tool") @MemberwiseInit(.public)
    public struct ToolPart {
        public let type: String  // tool-{name}
        public let toolCallId: String

        public var state: State
        public var providerExecuted: Bool?
        public var input: AnyCodable?
        public var callProviderMetadata: ChatMessage.ProviderMetadata?
        public var output: AnyCodable?
        public var preliminary: Bool?
        public var errorText: String?

        public var toolName: String { type.deletingPrefix("tool-") }

        public typealias State = DynamicToolPart.State
    }

    @PolymorphicCodable(identifier: "data") @MemberwiseInit(.public)
    public struct DataPart {
        public let type: String  // data-{name}
        public let id: String?
        public let data: AnyCodable?

        public var dataType: String { type.deletingPrefix("data-") }
    }

    public typealias ProviderMetadata = [String: [String: AnyCodable]]
}

@PolymorphicEnumEncodable(identifierCodingKey: "type")  // EnumEncodable only, decode is custom
public enum MessagePart: Decodable {
    case text(ChatMessage.TextPart)
    case reasoning(ChatMessage.ReasoningPart)
    case dynamicTool(ChatMessage.DynamicToolPart)
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
        case ChatMessage.DynamicToolPart.polymorphicIdentifier:
            self = .dynamicTool(try ChatMessage.DynamicToolPart(from: decoder))
        case ChatMessage.SourceURLPart.polymorphicIdentifier:
            self = .sourceURL(try ChatMessage.SourceURLPart(from: decoder))
        case ChatMessage.SourceDocumentPart.polymorphicIdentifier:
            self = .sourceDocument(try ChatMessage.SourceDocumentPart(from: decoder))
        case ChatMessage.FilePart.polymorphicIdentifier:
            self = .file(try ChatMessage.FilePart(from: decoder))
        case ChatMessage.StepStartPart.polymorphicIdentifier:
            self = .stepStart(try ChatMessage.StepStartPart(from: decoder))
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

extension String {
    fileprivate func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}
