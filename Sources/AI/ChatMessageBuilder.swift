import Foundation
import KarrotCodableKit

package struct ChatMessageBuilder {
    private var messageId: String?
    private var messageMetadata: AnyCodable?
    private var parts: [String: ChatMessage.Part] = [:]

    private var createdAt: Date = Date()
    private var textBuffer: String = ""
    private var reasoningBuffer: String = ""
    private var sources: [ChatMessage.Source] = []
    private var toolStates: [String: PendingToolInvocation] = [:]
    private var toolOrder: [String] = []
    private var hasStepStart: Bool = false
    private var finish: ChatMessageChunk.FinishFrame?
    private var dataDone: ChatMessageChunk.DataDoneFrame?
    private var lastError: String?

    package init() {}

    package mutating func apply(chunk: ChatMessageChunk) {
        switch chunk {
        case .textStart(let c):
            parts[c.id] = .text(.init(c))
        case .textDelta(let c):
            updateTextPart(c.id) { $0.apply(c) }
        case .textEnd(let c):
            updateTextPart(c.id) { $0.apply(c) }
        case .reasoningStart(let c):
            parts[c.id] = .reasoning(.init(c))
        case .reasoningDelta(let c):
            updateReasoningPart(c.id) { $0.apply(c) }
        case .reasoningEnd(let c):
            updateReasoningPart(c.id) { $0.apply(c) }
        case .toolInputStart(let c):
            parts[c.toolCallId] = .tool(.inputStreaming(.init(c)))
        case .toolInputDelta(let c):
            updateToolPart(c.toolCallId) { $0.apply(c) }
        case .toolInputAvailable(let c):
            parts[c.toolCallId] = .tool(.inputAvailable(.init(c)))
        case .toolInputError(let c):
            break
        case .toolOutputAvailable(let c):
            break
        case .toolOutputError(let c):
            break
        case .sourceURL(let c):
            parts[UUID().uuidString] = .sourceURL(
                .init(
                    sourceId: c.sourceId, url: c.url, title: c.title,
                    providerMetadata: c.providerMetadata))
        case .sourceDocument(let c):
            parts[UUID().uuidString] = .sourceDocument(
                .init(
                    sourceId: c.sourceId, mediaType: c.mediatype, title: c.title,
                    filename: c.filename, providerMetadata: c.providerMetadata))
        case .file(let c):  // TS types are probably wrong
            parts[UUID().uuidString] = .file(
                .init(
                    mediaType: c.mediatype, filename: nil,
                    url: c.url, providerMetadata: nil))
        case .data(let c):
            break
        case .error(let c):
            break
        case .startStep(let c):
            parts[UUID().uuidString] = .stepStart(.init())
        case .finishStep(let c):
            parts[UUID().uuidString] = .stepStart(.init())
        case .start(let c):
            messageId = c.messageId
            messageMetadata = c.messageMetadata
        case .finish(let c):
            messageMetadata = c.messageMetadata
        case .abort(let f):
            break
        case .messageMetadata(let f):
            messageMetadata = f.messageMetadata
        }
    }

    package func snapshot() -> ChatMessage {

    }

    private mutating func updateTextPart(
        _ id: String, _ updater: (inout ChatMessage.TextPart) -> Void
    ) {
        guard case .text(var part) = parts[id] else { return }
        updater(&part)
        parts[id] = .text(part)
    }

    private mutating func updateReasoningPart(
        _ id: String, _ updater: (inout ChatMessage.ReasoningPart) -> Void
    ) {
        guard case .reasoning(var part) = parts[id] else { return }
        updater(&part)
        parts[id] = .reasoning(part)
    }

    private mutating func updateToolPart(
        _ id: String, _ updater: (inout ChatMessage.ToolPart.InputStreamingState) -> Void
    ) {
        guard case .tool(let part) = parts[id] else { return }
        guard case .inputStreaming(var state) = part else { return }
        updater(&state)
        parts[id] = .tool(.inputStreaming(state))
    }

}

extension ChatMessage.TextPart {
    init(_ chunk: ChatMessageChunk.TextStart) {
        self.init(text: "", state: .streaming, providerMetadata: chunk.providerMetadata)
    }
    mutating func apply(_ chunk: ChatMessageChunk.TextDelta) {
        text += chunk.delta
        providerMetadata = chunk.providerMetadata
    }
    mutating func apply(_ chunk: ChatMessageChunk.TextEnd) {
        state = .done
        providerMetadata = chunk.providerMetadata
    }
}

extension ChatMessage.ReasoningPart {
    init(_ chunk: ChatMessageChunk.ReasoningStart) {
        self.init(text: "", state: .streaming, providerMetadata: chunk.providerMetadata)
    }
    mutating func apply(_ chunk: ChatMessageChunk.ReasoningDelta) {
        text += chunk.delta
        providerMetadata = chunk.providerMetadata
    }
    mutating func apply(_ chunk: ChatMessageChunk.ReasoningEnd) {
        state = .done
        providerMetadata = chunk.providerMetadata
    }
}

extension ChatMessage.ToolPart.InputStreamingState {
    init(_ chunk: ChatMessageChunk.ToolInputStart) {
        self.init(
            type: (chunk.dynamic == true ? "dynamic-tool" : "tool-\(chunk.toolName)"),
            toolCallId: chunk.toolCallId,
            providerExecuted: chunk.providerExecuted,
            input: nil)
    }
    mutating func apply(_ chunk: ChatMessageChunk.ToolInputDelta) {
        input = AnyCodable(input?.value as? String ?? "" + chunk.inputTextDelta)
    }
}

extension ChatMessage.ToolPart.InputAvailableState {
    init(_ chunk: ChatMessageChunk.ToolInputAvailable) {
        self.init(
            type: (chunk.dynamic == true ? "dynamic-tool" : "tool-\(chunk.toolName)"),
            toolCallId: chunk.toolCallId,
            providerExecuted: chunk.providerExecuted,
            input: chunk.input,
            callProviderMetadata: chunk.providerMetadata)
    }
}
