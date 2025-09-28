import AI
import Foundation
import ISO8601JSON
import KarrotCodableKit
import MemberwiseInit

// todo: add direct http request support
// todo: handle task timeout
// todo: implement cancel message (?)
@Observable
public class AgentClient: WebSocketClient.Delegate {
    // config
    private let instanceURL: URL
    private let headers: [String: String]?
    private let delegate: Delegate?
    private var ws: WebSocketClient!
    // state
    public private(set) var connected: Bool = false
    public private(set) var messages: [ChatMessage] = []
    private var chatTasks: [String: ChatTask] = [:]
    private var rpcTasks: [String: AnyRPCTask] = [:]

    public init(instanceURL: URL, headers: [String: String]? = nil, delegate: Delegate? = nil) {
        self.instanceURL = instanceURL
        self.headers = headers
        self.delegate = delegate

        let urlRequest = URLRequest(
            url: instanceURL.replacingInScheme("http", with: "ws")
        ).addingHeaders(headers)

        self.ws = WebSocketClient(
            delegate: self,
            urlRequest: urlRequest,
            messageFormat: .text)

        self.ws.connect()
    }

    public func loadInitialMessages(headers latestHeaders: [String: String]? = nil) async throws {
        let urlRequest = URLRequest(
            url: instanceURL.replacingInScheme("ws", with: "http").appending(path: "get-messages")
        ).addingHeaders(latestHeaders ?? self.headers)

        for attempt in 0...3 {
            do {
                let (data, _) = try await URLSession.shared.data(for: urlRequest)
                self.messages = try jsonDecoder.decode([ChatMessage].self, from: data)
                return
            } catch {
                if attempt == 3 { throw error }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func onMessage(text: String) {
        guard
            let incomingMessage = try? jsonDecoder.decode(
                IncomingMessage.self, from: text.data(using: .utf8) ?? Data())
        else {
            print("AgentClient: failed to parse incoming message: \(text)")
            return
        }

        switch incomingMessage {
        case .cf_agent_state(let msg):
            delegate?.onServerStateUpdate(msg.state, self)
            return
        case .cf_agent_mcp_servers(let msg):
            delegate?.onMcpUpdate(msg.mcp, self)
            return
        case .rpc(let msg):  // TODO: STREAMING SUPPORT
            guard let task = rpcTasks[msg.id] else { return }
            //
            guard let result = msg.result, msg.success == true else {
                // handle error
                task.reject(.responseError(id: msg.id, message: msg.error))
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
            guard var task = chatTasks[msg.id] else { return }
            // Apply chunks into the builder
            for chunk in ChatMessageChunk.parseAll(from: msg.body) {
                task.builder.apply(chunk: chunk)
            }
            // Persist updated builder state
            chatTasks[msg.id] = task
            // Create a snapshot and update local messages list
            guard let snapshot = task.builder.snapshot() else { return }
            upsertMessages([snapshot])
            // Handle completion
            if task.builder.done {
                if task.builder.error != nil {
                    // reject task
                    task.reject(.responseError(id: msg.id, message: msg.body))
                    chatTasks.removeValue(forKey: msg.id)
                } else {
                    // resolve task
                    task.resolve(snapshot)
                    chatTasks.removeValue(forKey: msg.id)
                    // advertise tool calls
                    for part in snapshot.parts {
                        if case .tool(let toolPart) = part,
                            case .inputAvailable = toolPart.state
                        {
                            delegate?.onToolCall(toolPart, self)
                        }
                        if case .dynamicTool(let toolPart) = part,
                            case .inputAvailable = toolPart.state
                        {
                            delegate?.onDynamicToolCall(toolPart, self)
                        }
                    }
                }
            }
            return
        case .cf_agent_chat_clear:
            self.messages = []
            return
        case .cf_agent_chat_messages(let msg):
            upsertMessages(msg.messages)
            return
        @unknown default:
            print("AgentClient: unknown type for incoming message: \(incomingMessage)")
            return
        }
    }

    func onMessage(data: Data) {
        fatalError("AgentClient: unexpected binary message: \(data)")
    }

    func onConnected() {
        connected = true
    }

    func onDisconnected(error: Error?) {
        connected = false
        delegate?.onDisconnected(error, self)
    }

    public func reconnect(
        every: Duration = .seconds(1.5),
        getHeaders: (() async -> [String: String])? = nil
    ) async -> Bool {
        func getURLRequest() async -> URLRequest {
            let headers = (await getHeaders?()) ?? self.headers
            return URLRequest(url: instanceURL.replacingInScheme("http", with: "ws"))
                .addingHeaders(headers)
        }
        let res = await ws.reconnect(every: every, retries: Int.max, getURLRequest: getURLRequest)
        if res { try? await loadInitialMessages(headers: await getHeaders?()) }  // todo: what if this fails?
        return res
    }

    public func sendMessage(
        _ parts: [ChatMessage.Part],
        body: [String: AnyEncodable] = [:]
    ) async throws(ChatError) -> ChatMessage {
        let messageId = "user_\(UUID().uuidString)"
        let message = ChatMessage(id: messageId, role: .user, metadata: nil, parts: parts)

        let result = await sendChatRequest(
            message: message,
            body: body,
            onSent: { messages.append(message) }
        )
        switch result {
        case .success(let message): return message
        case .failure(let error): throw error
        }
    }

    func sendChatRequest(
        message: ChatMessage,
        body: [String: AnyEncodable] = [:],
        onSent: () -> Void = {}
    ) async -> Result<ChatMessage, ChatError> {  // throws for send errors, returns failure for response errors

        let requestId = UUID().uuidString
        do {
            var body = body
            body["messages"] = [message]
            let requestInit = [
                "body": String(decoding: try jsonEncoder.encode(body), as: UTF8.self),
                "method": "POST",
            ]
            let chatReq = CFAgentUseChatRequest(id: requestId, init: requestInit)
            let chatReqData = try jsonEncoder.encode(chatReq)
            try await ws.send(data: chatReqData)  // make sure send succeeds before creating the task
        } catch {
            return .failure(.requestError(error))
        }

        return await withCheckedContinuation { cont in
            chatTasks[requestId] = ChatTask(
                builder: ChatMessageBuilder(),
                resolve: { r in cont.resume(returning: .success(r)) },
                reject: { e in cont.resume(returning: .failure(e)) }
            )
            onSent()  // make sure to call onSent after the task is created
        }
    }

    public func call<Args: Encodable & Collection, Payload: Decodable>(
        method: String,
        args: Args,
        resultType: Payload.Type = Payload.self
    ) async throws(RPCError) -> Payload where Args.Element: Encodable, Args.Index == Int {

        let result = await sendCall(
            method: method,
            args: args,
            resultType: resultType
        )
        switch result {
        case .success(let payload): return payload
        case .failure(let error): throw error
        }
    }

    func sendCall<Args: Encodable & Collection, Payload: Decodable>(
        method: String,
        args: Args,
        resultType: Payload.Type = Payload.self,
        onSent: () -> Void = {}
    ) async -> Result<Payload, RPCError> where Args.Element: Encodable, Args.Index == Int {

        let requestId = UUID().uuidString
        do {
            let rpcReq = RPCRequest(id: requestId, method: method, args: args)
            let rpcReqData = try jsonEncoder.encode(rpcReq)
            try await ws.send(data: rpcReqData)  // make sure send succeeds before creating the task
        } catch {
            return .failure(.requestError(error))
        }
        return await withCheckedContinuation { cont in
            rpcTasks[requestId] = RPCTask(
                onResolve: { r in cont.resume(returning: .success(r)) },
                onReject: { e in cont.resume(returning: .failure(e)) }
            )
            onSent()  // make sure to call onSent after the task is created
        }
    }

    public func addToolOutput(
        toolCallId toolCallIdTarget: String,
        output: AnyCodable?,
        preliminary: Bool? = nil
    ) async throws(ChatError) -> ChatMessage {
        guard let lastMsg = messages.last else {
            throw .requestedToolCallNotFound
        }

        var found: Bool = false

        let updatedParts = lastMsg.parts.map { part in
            switch part {
            case .tool(let toolPart) where toolPart.toolCallId == toolCallIdTarget:
                if case .inputAvailable = toolPart.state {
                    found = true
                    var new = toolPart
                    new.output = output
                    new.preliminary = preliminary
                    new.state = .outputAvailable
                    return ChatMessage.Part.tool(new)
                }
            case .dynamicTool(let toolPart) where toolPart.toolCallId == toolCallIdTarget:
                if case .inputAvailable = toolPart.state {
                    found = true
                    var new = toolPart
                    new.output = output
                    new.preliminary = preliminary
                    new.state = .outputAvailable
                    return ChatMessage.Part.dynamicTool(new)
                }
            default:
                break
            }
            return part
        }

        if !found {
            throw .requestedToolCallNotFound
        }

        let updatedMsg = ChatMessage(
            id: lastMsg.id,
            role: lastMsg.role,
            metadata: lastMsg.metadata,
            parts: updatedParts
        )

        let result = await sendChatRequest(
            message: updatedMsg,
            onSent: { messages[messages.count - 1] = updatedMsg }
        )
        switch result {
        case .success(let message): return message
        case .failure(let error): throw error
        }
    }

    func upsertMessages(_ incoming: [ChatMessage]) {
        var incoming = incoming
        // replace existing messages by incoming messages with the same id
        var newMessages = self.messages.map { existing in
            guard let incomingIdx = incoming.firstIndex(where: { $0.id == existing.id })
            else { return existing }  // keep original message
            return incoming.remove(at: incomingIdx)  // replace by incoming message
        }
        newMessages.append(contentsOf: incoming)  // concat brand new incoming messages
        self.messages = newMessages
    }

    public func clearHistory() async throws {
        let data = CFAgentChatClear()
        try await ws.send(data: try jsonEncoder.encode(data))
        self.messages = []
    }

    public func setState<State: Codable>(_ state: State) async throws {
        let data = CFAgentState(state: state)
        try await ws.send(data: try jsonEncoder.encode(data))
        delegate?.onClientStateUpdate(state, self)
    }

    public func cancelChatRequest(id: String) async throws {
        let data = CFAgentChatRequestCancel(id: id)
        try await ws.send(data: try jsonEncoder.encode(data))
        chatTasks.removeValue(forKey: id)
    }

    public func tryCancelAllChatRequests() async {
        let ids = Array(chatTasks.keys)
        for id in ids { try? await cancelChatRequest(id: id) }
    }

    public protocol Delegate {
        func onToolCall(_: ChatMessage.ToolPart, _: AgentClient)
        func onDynamicToolCall(_: ChatMessage.DynamicToolPart, _: AgentClient)
        func onClientStateUpdate<State: Codable>(_: State, _: AgentClient)
        func onServerStateUpdate<State: Codable>(_: State, _: AgentClient)
        func onMcpUpdate(_: MCPServersState, _: AgentClient)
        func onDisconnected(_: Error?, _: AgentClient)
    }
}

public enum RPCError: Error {
    case requestError(Error)
    case responseError(id: String, message: String?)
    case responseTypeMismatch(type: Decodable.Type)
}

protocol AnyRPCTask {
    func resolve(_: Codable)
    func reject(_: RPCError)
}

struct RPCTask<Result: Decodable>: AnyRPCTask {
    let onResolve: (Result) -> Void
    let onReject: (RPCError) -> Void

    func resolve(_ r: Codable) {
        do {
            onResolve(try jsonDecoder.decode(Result.self, from: try jsonEncoder.encode(r)))
        } catch {
            onReject(.responseTypeMismatch(type: Result.self))
        }
    }

    func reject(_ e: RPCError) {
        onReject(e)
    }
}

public enum ChatError: Error {
    case requestError(Error)
    case requestedToolCallNotFound  // addToolOutput only
    case responseError(id: String, message: String?)
}

struct ChatTask {
    var builder: ChatMessageBuilder
    let resolve: (ChatMessage) -> Void
    let reject: (ChatError) -> Void
}

extension URL {
    fileprivate func replacingInScheme(_ of: String, with: String) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return self }
        comps.scheme = comps.scheme?.replacingOccurrences(of: of, with: with)
        return comps.url ?? self
    }
}

extension URLRequest {
    fileprivate func addingHeaders(_ dict: [String: String]?) -> URLRequest {
        var req = self
        for (key, value) in dict ?? [:] {
            req.addValue(value, forHTTPHeaderField: key)
        }
        return req
    }
}

private let jsonDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
    return dec
}()

private let jsonEncoder = {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601withFractionalSeconds
    return enc
}()
