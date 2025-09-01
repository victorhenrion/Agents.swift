import Foundation
import KarrotCodableKit
import MemberwiseInit

// todo: add direct http request support
// todo: handle task timeout
// todo: implement cancel message (?)
@Observable
public class AgentClient<State: Codable>: WebSocketConnectionDelegate {
    private let wsUrl: URL
    private var ws: WebSocketConnection
    private let options: AgentClientOptions<State>
    private var chatTasks: [String: ChatTask] = [:]
    private var rpcTasks: [String: RPCTask<AnyCodable>] = [:]
    public private(set) var messages: [ChatMessage] = []

    public init(
        baseURL: URL,
        agentNamespace: String,
        instanceName: String,
        options: AgentClientOptions<State>
    ) async {
        self.options = options

        var urlComps = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        urlComps.scheme = urlComps.scheme?.replacingOccurrences(of: "http", with: "ws")
        urlComps.path = urlComps.path.appending("/\(camelCaseToKebabCase(agentNamespace))")
        urlComps.path = urlComps.path.appending("/\(instanceName)")
        self.wsUrl = urlComps.url!

        self.ws = WebSocketTaskConnection(
            url: wsUrl, headers: options.headers, messageFormat: .text
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
        var urlComps = URLComponents(url: wsUrl, resolvingAgainstBaseURL: true)!
        urlComps.scheme = urlComps.scheme?.replacingOccurrences(of: "ws", with: "http")
        urlComps.path = urlComps.path.appending("/get-messages")
        let url = urlComps.url!

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
                options.onServerStateUpdate?(msg.state as! State, self)
                return
            case .cf_agent_mcp_servers(let msg):
                options.onMcpUpdate?(msg.mcp, self)
                return
            case .rpc(let msg):
                // todo: actually build from the stream
                guard let task = rpcTasks[msg.id] else {
                    return
                }
                guard let result = msg.result, msg.success == true else {
                    // handle error
                    task.reject(AgentError.rpc(msg.error))
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
            case .cf_agent_use_chat_response(let msg):
                // todo: handle non-streaming response
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
            messages.append(message)
        }
    }

    public func call<Result: Codable>(
        method: String,
        args: [AnyCodable]
    ) async throws -> Result {

        let requestId = UUID().uuidString

        let rpcReq = RPCRequest(id: requestId, method: method, args: args)
        let rpcReqData = try jsonEncoder.encode(rpcReq)

        return try await withCheckedThrowingContinuation { cont in

            rpcTasks[requestId] = RPCTask(
                resolve: { r in cont.resume(returning: r as! Result) },
                reject: { e in cont.resume(throwing: e) }
                )

            ws.send(data: rpcReqData)
        }
    }

    func upsertAssistantMessage(_ message: ChatMessage) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
        }
    }

    public func setMessages(_ messages: [ChatMessage]) {
        self.messages = messages
        let data = CFAgentChatMessages(messages: messages)
        ws.send(data: try! jsonEncoder.encode(data))
    }

    public func clearHistory() {
        self.messages = []
        let data = CFAgentChatClear()
        ws.send(data: try! jsonEncoder.encode(data))
    }

    public func setState(_ state: State) {
        let data = CFAgentState(state: state)
        ws.send(data: try! jsonEncoder.encode(data))
        options.onClientStateUpdate?(state, self)
    }

    public func cancelChatRequest(id: String) {
        chatTasks.removeValue(forKey: id)
        let data = CFAgentChatRequestCancel(id: id)
        ws.send(data: try! jsonEncoder.encode(data))
    }

    public func cancelAllChatRequests() {
        let ids = Array(chatTasks.keys)
        for id in ids { cancelChatRequest(id: id) }
    }
}

@MemberwiseInit(.public)
public struct AgentClientOptions<State: Codable> {
    public let onClientStateUpdate: ((State, AgentClient<State>) -> Void)?
    public let onServerStateUpdate: ((State, AgentClient<State>) -> Void)?
    public let onMcpUpdate: ((MCPServersState, AgentClient<State>) -> Void)?
    public let headers: [String: String]?
}

struct RPCTask<Result: Codable> {
    let resolve: (Result) -> Void
    let reject: (Error) -> Void
}

struct ChatTask {
    var builder: ChatMessageBuilder
    let resolve: (ChatMessage) -> Void
    let reject: (Error) -> Void
}

public enum AgentError: Error {
    case rpc(String?)
    case chat(String?)
}
