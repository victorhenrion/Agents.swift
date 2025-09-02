import Foundation
import KarrotCodableKit
import MemberwiseInit

// todo: add direct http request support
// todo: handle task timeout
// todo: implement cancel message (?)
@Observable
public class AgentClient<State: Codable>: WebSocketConnectionDelegate {
    private let instanceURL: URL
    private var ws: WebSocketConnection
    private let options: AgentClientOptions<State>
    private var chatTasks: [String: ChatTask] = [:]
    private var rpcTasks: [String: AnyRPCTask] = [:]
    public private(set) var messages: [ChatMessage] = []

    public init(
        baseURL: URL,
        agentNamespace: String,
        instanceName: String,
        options: AgentClientOptions<State>
    ) async {
        self.options = options

        self.instanceURL =
            baseURL
            .appending(path: camelCaseToKebabCase(agentNamespace))
            .appending(path: instanceName)

        self.ws = WebSocketTaskConnection(
            url: instanceURL, headers: options.headers, messageFormat: .text
        )
        ws.delegate = self

        do {
            try await loadInitialMessages()
        } catch {
            print("Failed to load initial messages: \(error)")
        }

        ws.connect()
    }

    func loadInitialMessages() async throws {
        let url = self.instanceURL.appending(path: "get-messages")

        var request = URLRequest(url: url)
        if let headers = options.headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        self.messages = try jsonDecoder.decode([ChatMessage].self, from: data)
    }

    func onMessage(text: String) {
        do {
            let incomingMessage = try jsonDecoder.decode(
                IncomingMessage.self, from: text.data(using: .utf8) ?? Data()
            )

            switch incomingMessage {
            case .cf_agent_state(let msg):
                if let state = msg.state as? State {
                    options.onServerStateUpdate?(state, self)
                }  // fails silently
                return
            case .cf_agent_mcp_servers(let msg):
                options.onMcpUpdate?(msg.mcp, self)
                return
            case .rpc(let msg):  // TODO: STREAMING SUPPORT
                guard let task = rpcTasks[msg.id] else {
                    return
                }
                guard let result = msg.result, msg.success == true else {
                    // handle error
                    task.reject(AgentError.rpcError(id: msg.id, error: msg.error))
                    rpcTasks.removeValue(forKey: msg.id)
                    return
                }
                guard let done = msg.done else {
                    // handle non-streaming result
                    task.resolve(result)
                    rpcTasks.removeValue(forKey: msg.id)
                    return
                }
                if done {
                    // handle result
                    task.resolve(result)
                    rpcTasks.removeValue(forKey: msg.id)
                }
                return
            case .cf_agent_use_chat_response(let msg):  // streaming only
                guard var task = chatTasks[msg.id] else {
                    return
                }
                // Apply frames into the builder
                for frame in ChatMessageStreamFrame.parseAll(from: msg.body) {
                    task.builder.apply(frame: frame)
                }
                // Persist updated builder state
                chatTasks[msg.id] = task
                // Create a snapshot and update local messages list
                let snapshot = task.builder.snapshot()
                upsertAssistantMessage(snapshot)
                // Handle completion
                if msg.done == true {
                    task.resolve(snapshot)
                    chatTasks.removeValue(forKey: msg.id)
                    // advertise tool calls
                    for p in snapshot.parts {
                        if case .toolInvocation(let p) = p, p.toolInvocation.state == .call {
                            options.onToolCall?(p.toolInvocation, self)
                        }
                    }
                }
                return
            case .cf_agent_chat_clear:
                self.messages = []
                return
            case .cf_agent_chat_messages(let msg):
                self.messages = msg.messages
                return
            @unknown default:
                return
            }
        } catch {
            print("AgentClient: error processing message: \(error)")
        }
    }

    func onMessage(data: Data) {
        print("AgentClient: unexpected binary message: \(data)")
    }

    func onConnected() {

    }

    func onDisconnected(error: Error?) {

    }

    func onError(error: Error) {

    }

    public func sendMessage(
        message: ChatMessage,
        body: [String: AnyEncodable] = [:]
    ) async throws -> ChatMessage {
        return try await sendChatRequest(
            message: message,
            body: body,
            onSent: { messages.append(message) }
        )
    }

    func sendChatRequest(
        message: ChatMessage,
        body: [String: AnyEncodable] = [:],
        onSent: () -> Void
    ) async throws -> ChatMessage {

        var body = body
        body["messages"] = [message]

        let requestId = UUID().uuidString
        let requestInit = [
            "body": String(decoding: try jsonEncoder.encode(body), as: UTF8.self),
            "method": "POST",
        ]

        let chatReq = CFAgentUseChatRequest(id: requestId, init: requestInit)
        let chatReqData = try jsonEncoder.encode(chatReq)

        return try await withCheckedThrowingContinuation { cont in

            chatTasks[requestId] = ChatTask(
                builder: ChatMessageBuilder(),
                resolve: { r in cont.resume(returning: r) },
                reject: { e in cont.resume(throwing: e) }
            )

            ws.send(data: chatReqData)
            onSent()
        }
    }

    public func call<Args: Encodable & Collection, Result: Decodable>(
        method: String,
        args: Args,
        resultType: Result.Type = Result.self
    ) async throws -> Result
    where Args.Element: Encodable, Args.Index == Int {

        let requestId = UUID().uuidString

        let rpcReq = RPCRequest(id: requestId, method: method, args: args)
        let rpcReqData = try jsonEncoder.encode(rpcReq)

        return try await withCheckedThrowingContinuation { cont in

            rpcTasks[requestId] = RPCTask(
                onResolve: { r in cont.resume(returning: r) },
                onReject: { e in cont.resume(throwing: e) }
            )

            ws.send(data: rpcReqData)
        }
    }

    public func addToolResult(
        toolCallId: String,
        result: AnyCodable?
    ) async throws -> ChatMessage {
        guard let lastMsg = messages.last else {
            throw AgentError.toolCallNotFound(id: toolCallId, "No messages")
        }

        var found: Bool = false

        let updatedParts = lastMsg.parts.map { part in
            switch part {
            case .toolInvocation(let part) where part.toolInvocation.toolCallId == toolCallId:
                found = true
                let prev = part.toolInvocation
                return ChatMessage.Part.toolInvocation(
                    .init(
                        toolInvocation: .init(
                            state: .result,
                            toolCallId: prev.toolCallId,
                            toolName: prev.toolName,
                            args: prev.args,
                            result: result,
                            step: prev.step,
                        )
                    )
                )
            default:
                return part
            }
        }

        if !found {
            throw AgentError.toolCallNotFound(id: toolCallId)
        }

        let updatedMsg = ChatMessage(
            id: lastMsg.id,
            createdAt: lastMsg.createdAt,
            experimental_attachments: lastMsg.experimental_attachments,
            role: lastMsg.role,
            annotations: lastMsg.annotations,
            parts: updatedParts
        )

        return try await sendChatRequest(
            message: updatedMsg,
            onSent: { messages[messages.count - 1] = updatedMsg }
        )
    }

    func upsertAssistantMessage(_ message: ChatMessage) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
        }
    }

    public func setMessages(_ messages: [ChatMessage]) throws {
        let data = CFAgentChatMessages(messages: messages)
        ws.send(data: try jsonEncoder.encode(data))
        self.messages = messages
    }

    public func clearHistory() {
        let data = CFAgentChatClear()
        ws.send(data: try! jsonEncoder.encode(data))  // should be safe
        self.messages = []
    }

    public func setState(_ state: State) throws {
        let data = CFAgentState(state: state)
        ws.send(data: try jsonEncoder.encode(data))
        options.onClientStateUpdate?(state, self)
    }

    public func cancelChatRequest(id: String) {
        let data = CFAgentChatRequestCancel(id: id)
        ws.send(data: try! jsonEncoder.encode(data))  // should be safe
        chatTasks.removeValue(forKey: id)
    }

    public func cancelAllChatRequests() {
        let ids = Array(chatTasks.keys)
        for id in ids { cancelChatRequest(id: id) }
    }
}

@MemberwiseInit(.public)
public struct AgentClientOptions<State: Codable> {
    public let onToolCall: ((ChatMessage.ToolInvocation, AgentClient<State>) -> Void)?
    public let onClientStateUpdate: ((State, AgentClient<State>) -> Void)?
    public let onServerStateUpdate: ((State, AgentClient<State>) -> Void)?
    public let onMcpUpdate: ((MCPServersState, AgentClient<State>) -> Void)?
    public let headers: [String: String]?
}

protocol AnyRPCTask {
    func resolve(_: Codable)
    func reject(_: Error)
}

struct RPCTask<Result: Decodable>: AnyRPCTask {
    let onResolve: (Result) -> Void
    let onReject: (Error) -> Void

    func resolve(_ r: Codable) {
        do {
            onResolve(try jsonDecoder.decode(Result.self, from: try jsonEncoder.encode(r)))
        } catch {
            onReject(AgentError.rpcResultMismatch(type: Result.self))
        }
    }

    func reject(_ e: Error) {
        onReject(e)
    }
}

struct ChatTask {
    var builder: ChatMessageBuilder
    let resolve: (ChatMessage) -> Void
    let reject: (Error) -> Void
}

public enum AgentError: Error {
    case toolCallNotFound(id: String, String? = nil)
    case rpcError(id: String, error: String?)
    case rpcResultMismatch(type: Decodable.Type)
}
