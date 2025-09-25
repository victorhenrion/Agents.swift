import Foundation
import KarrotCodableKit
import OrderedCollections

package struct ChatMessageBuilder {
    private var messageId: String?
    private var messageMetadata: AnyCodable?
    private var parts = OrderedDictionary<String, ChatMessage.Part>()

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
            parts[c.toolCallId] = c.dynamic == true ? .dynamicTool(.init(c)) : .tool(.init(c))
        case .toolInputDelta(let c):
            if case .dynamicTool(_) = parts[c.toolCallId] {
                updateDynamicToolPart(c.toolCallId) { $0.apply(c) }
            } else {
                updateToolPart(c.toolCallId) { $0.apply(c) }
            }
        case .toolInputAvailable(let c):
            parts[c.toolCallId] = c.dynamic == true ? .dynamicTool(.init(c)) : .tool(.init(c))
        case .toolInputError(let c):
            break  // TODO: handle this (not sure how the spec does it)
        case .toolOutputAvailable(let c):
            c.dynamic == true
                ? updateDynamicToolPart(c.toolCallId) { $0.apply(c) }
                : updateToolPart(c.toolCallId) { $0.apply(c) }
        case .toolOutputError(let c):
            c.dynamic == true
                ? updateDynamicToolPart(c.toolCallId) { $0.apply(c) }
                : updateToolPart(c.toolCallId) { $0.apply(c) }
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
        case .file(let c):
            parts[UUID().uuidString] = .file(
                .init(
                    mediaType: c.mediatype, filename: nil,  // TS types are probably wrong (nil filename?)
                    url: c.url, providerMetadata: nil))
        case .data(let c):
            parts[UUID().uuidString] = .data(.init(type: c.type, id: c.id, data: c.data))
        case .error(let c):
            break  // TODO: handle this
        case .startStep(_):
            parts[UUID().uuidString] = .stepStart(.init())
        case .finishStep(_):
            parts[UUID().uuidString] = .stepStart(.init())
        case .start(let c):
            messageId = c.messageId
            messageMetadata = c.messageMetadata
        case .finish(let c):
            messageMetadata = c.messageMetadata
        case .abort(_):
            break  //TODO: handle this maybe
        case .messageMetadata(let m):
            messageMetadata = m.messageMetadata
        }
        // (no cases should be missed)
    }

    package func snapshot() -> ChatMessage? {
        guard let messageId = messageId else { return nil }  // means missing start frame

        return ChatMessage(
            id: messageId,
            role: .assistant,
            metadata: messageMetadata,
            parts: parts.values.elements
        )
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
        _ id: String, _ updater: (inout ChatMessage.ToolPart) -> Void
    ) {
        guard case .tool(var part) = parts[id] else { return }
        updater(&part)
        parts[id] = .tool(part)
    }

    private mutating func updateDynamicToolPart(
        _ id: String, _ updater: (inout ChatMessage.DynamicToolPart) -> Void
    ) {
        guard case .dynamicTool(var part) = parts[id] else { return }
        updater(&part)
        parts[id] = .dynamicTool(part)
    }
}

extension ChatMessage.TextPart {
    fileprivate init(_ chunk: ChatMessageChunk.TextStart) {
        self.init(text: "", state: .streaming, providerMetadata: chunk.providerMetadata)
    }
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.TextDelta) {
        text += chunk.delta
        providerMetadata = chunk.providerMetadata
    }
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.TextEnd) {
        state = .done
        providerMetadata = chunk.providerMetadata
    }
}

extension ChatMessage.ReasoningPart {
    fileprivate init(_ chunk: ChatMessageChunk.ReasoningStart) {
        self.init(text: "", state: .streaming, providerMetadata: chunk.providerMetadata)
    }
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.ReasoningDelta) {
        text += chunk.delta
        providerMetadata = chunk.providerMetadata
    }
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.ReasoningEnd) {
        providerMetadata = chunk.providerMetadata
        state = .done
    }
}

extension ChatMessage.AnyToolPart {
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.ToolInputDelta) {
        input = AnyCodable(input?.value as? String ?? "" + chunk.inputTextDelta)
    }
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.ToolOutputAvailable) {
        providerExecuted = chunk.providerExecuted
        output = chunk.output
        preliminary = chunk.preliminary
        state = .outputAvailable
    }
    fileprivate mutating func apply(_ chunk: ChatMessageChunk.ToolOutputError) {
        providerExecuted = chunk.providerExecuted
        errorText = chunk.errorText
        state = .outputError
    }
}

extension ChatMessage.ToolPart {
    fileprivate init(_ chunk: ChatMessageChunk.ToolInputStart) {
        self.init(
            type: "tool-\(chunk.toolName)",
            toolCallId: chunk.toolCallId,
            state: .inputStreaming,
            providerExecuted: chunk.providerExecuted,
            input: nil,
            callProviderMetadata: nil,
            output: nil,
            preliminary: nil,
            errorText: nil
        )
    }
    fileprivate init(_ chunk: ChatMessageChunk.ToolInputAvailable) {
        self.init(
            type: "tool-\(chunk.toolName)",
            toolCallId: chunk.toolCallId,
            state: .inputAvailable,
            providerExecuted: chunk.providerExecuted,
            input: chunk.input,
            callProviderMetadata: chunk.providerMetadata,
            output: nil,
            preliminary: nil,
            errorText: nil
        )
    }
}

extension ChatMessage.DynamicToolPart {
    fileprivate init(_ chunk: ChatMessageChunk.ToolInputStart) {
        self.init(
            toolName: chunk.toolName,
            toolCallId: chunk.toolCallId,
            state: .inputStreaming,
            providerExecuted: chunk.providerExecuted,
            input: nil,
            callProviderMetadata: nil,
            output: nil,
            preliminary: nil,
            errorText: nil
        )
    }
    fileprivate init(_ chunk: ChatMessageChunk.ToolInputAvailable) {
        self.init(
            toolName: chunk.toolName,
            toolCallId: chunk.toolCallId,
            state: .inputAvailable,
            providerExecuted: chunk.providerExecuted,
            input: chunk.input,
            callProviderMetadata: chunk.providerMetadata,
            output: nil,
            preliminary: nil,
            errorText: nil
        )
    }
}
