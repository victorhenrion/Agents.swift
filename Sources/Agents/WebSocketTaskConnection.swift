import Foundation

public enum WebSocketMessageFormat {
    case preserve  // default: preserve frame type (text stays text, data stays data)
    case text  // force both directions to be text frames
    case binary  // force both directions to be binary frames
}

protocol WebSocketConnection {
    func send(text: String)
    func send(data: Data)
    func connect()
    func disconnect()
    var delegate: WebSocketConnectionDelegate! { get set }

    // NEW: control how frames are sent and delivered
    var messageFormat: WebSocketMessageFormat { get set }
    var textEncoding: String.Encoding { get set }
}

protocol WebSocketConnectionDelegate {
    func onConnected()
    func onDisconnected(error: Error?)
    func onError(error: Error)
    func onMessage(text: String)
    func onMessage(data: Data)
}

class WebSocketTaskConnection: NSObject, WebSocketConnection, URLSessionWebSocketDelegate {
    var delegate: WebSocketConnectionDelegate!
    let delegateQueue = OperationQueue()
    var urlSession: URLSession!
    var webSocketTask: URLSessionWebSocketTask!

    // NEW: format & encoding knobs (with sensible defaults)
    var messageFormat: WebSocketMessageFormat
    var textEncoding: String.Encoding

    init(
        url inputURL: URL,
        headers: [String: String]? = nil,
        messageFormat: WebSocketMessageFormat = .preserve,
        textEncoding: String.Encoding = .utf8
    ) {
        let url = {
            guard var c = URLComponents(url: inputURL, resolvingAgainstBaseURL: false)
            else { return inputURL }
            c.scheme = c.scheme?.replacingOccurrences(of: "http", with: "ws")
            return c.url ?? inputURL
        }()

        self.messageFormat = messageFormat
        self.textEncoding = textEncoding
        super.init()
        self.urlSession = URLSession(
            configuration: .default, delegate: self, delegateQueue: self.delegateQueue)

        if let headers = headers, !headers.isEmpty {
            var request = URLRequest(url: url)
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
            self.webSocketTask = self.urlSession.webSocketTask(with: request)
        } else {
            self.webSocketTask = self.urlSession.webSocketTask(with: url)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol `protocol`: String?
    ) {
        self.delegate.onConnected()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        self.delegate.onDisconnected(error: nil)
    }

    func connect() {
        webSocketTask.resume()
        listen()
    }

    func disconnect() {
        webSocketTask.cancel(with: .goingAway, reason: nil)
    }

    private func listen() {
        webSocketTask.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.delegate.onError(error: error)

            case .success(let message):
                switch message {
                case .string(let text):
                    switch self.messageFormat {
                    case .preserve, .text:
                        self.delegate.onMessage(text: text)
                    case .binary:
                        // Convert text to data for binary consumers
                        let data = text.data(using: self.textEncoding) ?? Data(text.utf8)
                        self.delegate.onMessage(data: data)
                    }

                case .data(let data):
                    switch self.messageFormat {
                    case .preserve, .binary:
                        self.delegate.onMessage(data: data)
                    case .text:
                        // Try to decode as text; fall back to base64 string
                        if let s = String(data: data, encoding: self.textEncoding) {
                            self.delegate.onMessage(text: s)
                        } else {
                            let b64 = data.base64EncodedString()
                            self.delegate.onMessage(text: b64)
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

    func send(text: String) {
        switch messageFormat {
        case .preserve, .text:
            webSocketTask.send(.string(text)) { [weak self] error in
                if let error = error { self?.delegate.onError(error: error) }
            }

        case .binary:
            // Force to binary frame
            let data = text.data(using: textEncoding) ?? Data(text.utf8)
            webSocketTask.send(.data(data)) { [weak self] error in
                if let error = error { self?.delegate.onError(error: error) }
            }
        }
    }

    func send(data: Data) {
        switch messageFormat {
        case .preserve, .binary:
            webSocketTask.send(.data(data)) { [weak self] error in
                if let error = error { self?.delegate.onError(error: error) }
            }

        case .text:
            // Try to make a text frame from the data; if not decodable, send base64 text
            let text = String(data: data, encoding: textEncoding) ?? data.base64EncodedString()
            webSocketTask.send(.string(text)) { [weak self] error in
                if let error = error { self?.delegate.onError(error: error) }
            }
        }
    }
}
