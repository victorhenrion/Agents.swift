import Foundation
import KarrotCodableKit
import MemberwiseInit

@PolymorphicCodable(identifier: "cf_agent_chat_clear")
struct CFAgentChatClear {
    let type = "cf_agent_chat_clear"
}

@PolymorphicCodable(identifier: "cf_agent_chat_messages")
struct CFAgentChatMessages {
    let type = "cf_agent_chat_messages"
    let messages: [ChatMessage]
}

@PolymorphicCodable(identifier: "cf_agent_mcp_servers")
struct CFAgentMcpServers {
    let type = "cf_agent_mcp_servers"
    let mcp: MCPServersState
}

@MemberwiseInit(.public)
public struct MCPServersState: Codable {
    public let servers: [String: MCPServer]
    public let tools: [Tool]
    public let prompts: [Prompt]
    public let resources: [Resource]

    public typealias Tool = [String: AnyCodable]  // placeholder for more precise type
    public typealias Prompt = [String: AnyCodable]  // placeholder for more precise type
    public typealias Resource = [String: AnyCodable]  // placeholder for more precise type
}

@MemberwiseInit(.public)
public struct MCPServer: Codable {
    public let name: String
    public let server_url: String
    public let auth_url: String?
    public let state: State
    public let instructions: String?
    public let capabilities: Capabilities?

    public enum State: String, Codable {
        case authenticating
        case connecting
        case ready
        case discovering
        case failed
    }

    public typealias Capabilities = [String: AnyCodable]  // placeholder for more precise type
}

@PolymorphicCodable(identifier: "cf_agent_state")
struct CFAgentState<State: Codable> {
    let type = "cf_agent_state"
    let state: State
}

//# region Incoming only
@PolymorphicEnumDecodable(identifierCodingKey: "type")
enum IncomingMessage {
    case cf_agent_chat_clear(CFAgentChatClear)
    case cf_agent_chat_messages(CFAgentChatMessages)
    case cf_agent_mcp_servers(CFAgentMcpServers)
    case cf_agent_state(CFAgentState<AnyCodable>)
    case cf_agent_use_chat_response(CFAgentUseChatResponse)
    case rpc(RPCResponse<AnyCodable>)
}

@PolymorphicDecodable(identifier: "cf_agent_use_chat_response")
struct CFAgentUseChatResponse {
    let type = "cf_agent_use_chat_response"
    let id: String
    let body: String
    let done: Bool?
}

@PolymorphicDecodable(identifier: "rpc")
struct RPCResponse<Result: Codable> {
    let type = "rpc"
    let id: String
    let success: Bool
    let result: Result?
    let done: Bool?
    let error: String?
}
//#endregion

//# region Outgoing only
@PolymorphicEnumEncodable(identifierCodingKey: "type")
enum OutgoingMessage {
    case cf_agent_chat_clear(CFAgentChatClear)
    case cf_agent_chat_messages(CFAgentChatMessages)
    case cf_agent_chat_request_cancel(CFAgentChatRequestCancel)
    case cf_agent_mcp_servers(CFAgentMcpServers)
    case cf_agent_state(CFAgentState<AnyCodable>)
    case cf_agent_use_chat_request(CFAgentUseChatRequest)
    case rpc(RPCRequest<[AnyEncodable]>)
}

@PolymorphicEncodable(identifier: "cf_agent_chat_request_cancel")
struct CFAgentChatRequestCancel {
    let type = "cf_agent_chat_request_cancel"
    let id: String
}

@PolymorphicEncodable(identifier: "cf_agent_use_chat_request")
struct CFAgentUseChatRequest {
    let type = "cf_agent_use_chat_request"
    let id: String
    let `init`: [String: String]
}

@PolymorphicEncodable(identifier: "rpc")
struct RPCRequest<Args: Encodable & Collection> where Args.Element: Encodable, Args.Index == Int {
    let type = "rpc"
    let id: String
    let method: String
    let args: Args  // an array of args
}
//# endregion
