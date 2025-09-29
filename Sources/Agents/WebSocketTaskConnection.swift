import Foundation

class WebSocketClient: NSObject, URLSessionWebSocketDelegate {
    // config
    private weak var delegate: Delegate?
    let messageFormat: MessageFormat
    let textEncoding: String.Encoding
    // state
    private let urlSessionQueue = OperationQueue()
    private(set) var urlSession: URLSession!
    private(set) var webSocketTask: URLSessionWebSocketTask!
    private(set) var reconnectTask: Task<Bool, Never>?
    private(set) var isOpen: Bool = false

    init(
        delegate: Delegate?,
        urlRequest: URLRequest,
        messageFormat: MessageFormat = .preserve,
        textEncoding: String.Encoding = .utf8
    ) {
        self.delegate = delegate
        self.messageFormat = messageFormat
        self.textEncoding = textEncoding
        super.init()
        self.urlSession = URLSession(
            configuration: .default, delegate: self, delegateQueue: self.urlSessionQueue)
        self.webSocketTask = self.urlSession.webSocketTask(with: urlRequest)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol `protocol`: String?
    ) {
        self.isOpen = true
        self.delegate?.onConnected()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        self.isOpen = false
        self.delegate?.onDisconnected(error: nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        self.isOpen = false
        self.delegate?.onDisconnected(error: error)
    }

    // bad because we recreate a connection with each retry and always wait for the whole duration, but good enough for now
    public func reconnect(
        every: Duration,
        retries maxRetries: Int,
        getURLRequest: @escaping () async -> URLRequest
    ) async -> Bool {
        // already connected
        if self.isOpen { return true }
        // reconnect already in progress
        if let task = reconnectTask, !task.isCancelled { return await task.value }
        // start task
        self.reconnectTask?.cancel()
        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self = self else { return false }
            defer { self.reconnectTask = nil }
            for _ in 0..<maxRetries {
                // connected or cancelled
                if self.isOpen || Task.isCancelled { break }
                // reconnect
                self.webSocketTask.cancel(with: .goingAway, reason: nil)
                self.webSocketTask = self.urlSession.webSocketTask(with: await getURLRequest())
                self.isOpen = false  // ensure it didn't change in the meantime
                self.connect()
                // wait
                try? await Task.sleep(for: every)
            }
            return self.isOpen
        }
        // set task and return promise
        self.reconnectTask = task
        return await task.value
    }

    func connect() {
        webSocketTask.resume()
        listen()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
        isOpen = false
    }

    private func listen() {
        webSocketTask.receive { [weak self] result in
            guard let self = self else { return }
            guard let delegate = self.delegate else { return }
            switch result {
            case .failure(let error):
                self.isOpen = false
                delegate.onDisconnected(error: error)

            case .success(let message):
                switch message {
                case .string(let text):
                    switch self.messageFormat {
                    case .preserve, .text:
                        delegate.onMessage(text: text)
                    case .binary:
                        // Convert text to data for binary consumers
                        let data = text.data(using: self.textEncoding) ?? Data(text.utf8)
                        delegate.onMessage(data: data)
                    }

                case .data(let data):
                    switch self.messageFormat {
                    case .preserve, .binary:
                        delegate.onMessage(data: data)
                    case .text:
                        // Try to decode as text; fall back to base64 string
                        if let s = String(data: data, encoding: self.textEncoding) {
                            delegate.onMessage(text: s)
                        } else {
                            let b64 = data.base64EncodedString()
                            delegate.onMessage(text: b64)
                        }
                    }

                @unknown default:
                    // Swallow unknown cases instead of crashing
                    break
                }

                // Keep listening
                self.listen()
            }
        }
    }

    func send(text: String) async throws {
        return try await withCheckedThrowingContinuation { [weak self] cont in
            guard let self = self else { return }
            switch self.messageFormat {
            case .preserve, .text:
                self.webSocketTask.send(.string(text)) { error in
                    if let error = error { cont.resume(throwing: error) } else { cont.resume() }
                }

            case .binary:
                // Force to binary frame
                let data = text.data(using: self.textEncoding) ?? Data(text.utf8)
                self.webSocketTask.send(.data(data)) { error in
                    if let error = error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    func send(data: Data) async throws {
        return try await withCheckedThrowingContinuation { [weak self] cont in
            guard let self = self else { return }
            switch self.messageFormat {
            case .preserve, .binary:
                self.webSocketTask.send(.data(data)) { error in
                    if let error = error { cont.resume(throwing: error) } else { cont.resume() }
                }

            case .text:
                // Try to make a text frame from the data; if not decodable, send base64 text
                let text =
                    String(data: data, encoding: self.textEncoding) ?? data.base64EncodedString()
                self.webSocketTask.send(.string(text)) { error in
                    if let error = error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    deinit {
        disconnect()
    }

    protocol Delegate: AnyObject {
        func onConnected()
        func onDisconnected(error: Error?)
        func onMessage(text: String)
        func onMessage(data: Data)
    }

    enum MessageFormat {
        case preserve  // default: preserve frame type (text stays text, data stays data)
        case text  // force both directions to be text frames
        case binary  // force both directions to be binary frames
    }
}
