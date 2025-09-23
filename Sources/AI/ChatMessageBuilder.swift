import Foundation
import KarrotCodableKit

package struct ChatMessageBuilder {
    private(set) var assistantMessageId: String?
    private var createdAt: Date = Date()
    private var textBuffer: String = ""
    private var reasoningBuffer: String = ""
    private var sources: [ChatMessage.Source] = []
    private var toolStates: [String: PendingToolInvocation] = [:]
    private var toolOrder: [String] = []
    private var hasStepStart: Bool = false
    private var finish: ChatMessageStreamFrame.FinishFrame?
    private var dataDone: ChatMessageStreamFrame.DataDoneFrame?
    private var lastError: String?

    package init() {}

    package mutating func apply(frames: [ChatMessageStreamFrame]) {
        for f in frames { apply(frame: f) }
    }

    package mutating func apply(frame: ChatMessageStreamFrame) {
        switch frame {
        case .start(let s): handleStart(s)
        case .text(let t): handleText(t)
        case .reasoning(let r): handleReasoning(r)
        case .source(let s): addSource(s)
        case .toolCallStart(let t): handleToolStart(t)
        case .toolCallDelta(let d): handleToolDelta(d)
        case .toolCall(let t): handleToolCall(t)
        case .toolResult(let r): handleToolResult(r)
        case .finish(let f): finish = f
        case .dataDone(let d): dataDone = d
        case .error(let m): lastError = m
        case .unknown(_): break
        }
    }

    package func snapshot() -> ChatMessage {
        var parts: [ChatMessage.Part] = []
        if hasStepStart { parts.append(.stepStart(ChatMessage.StepStartPart())) }
        if !reasoningBuffer.isEmpty {
            parts.append(.reasoning(ChatMessage.ReasoningPart(reasoning: reasoningBuffer)))
        }
        if !textBuffer.isEmpty { parts.append(.text(ChatMessage.TextPart(text: textBuffer))) }
        parts.append(
            contentsOf: toolOrder.compactMap { id in
                guard let s = toolStates[id] else { return nil }
                let inv = ChatMessage.ToolInvocation(
                    state: s.state,
                    toolCallId: s.toolCallId,
                    toolName: s.toolName,
                    args: s.args ?? AnyCodable(nil as Any?),
                    result: s.result,
                    step: nil
                )
                return .toolInvocation(ChatMessage.ToolInvocationPart(toolInvocation: inv))
            })
        parts.append(contentsOf: sources.map { .source(ChatMessage.SourcePart(source: $0)) })
        let annotations: [AnyCodable] = buildAnnotations()
        return ChatMessage(
            id: assistantMessageId ?? UUID().uuidString,
            createdAt: createdAt,
            experimental_attachments: [],
            role: .assistant,
            annotations: annotations.isEmpty ? [] : annotations,
            parts: parts
        )
    }

    private func buildAnnotations() -> [AnyCodable] {
        func pack(_ reason: String?, _ usage: ChatMessageStreamFrame.FinishFrame.Usage?)
            -> [AnyCodable]
        {
            var dict: [String: Any] = [:]
            if let reason { dict["finishReason"] = reason }
            if let usage {
                var u: [String: Any] = [:]
                if let p = usage.promptTokens { u["promptTokens"] = p }
                if let c = usage.completionTokens { u["completionTokens"] = c }
                dict["usage"] = u
            }
            if let err = lastError { dict["error"] = err }
            return dict.isEmpty ? [] : [AnyCodable(dict)]
        }
        if let f = finish { return pack(f.finishReason, f.usage) }
        if let d = dataDone { return pack(d.finishReason, d.usage) }
        if let err = lastError { return [AnyCodable(["error": err])] }
        return []
    }

    // MARK: - Frame handlers

    private mutating func handleStart(_ s: ChatMessageStreamFrame.StartFrame) {
        if let mid = s.messageId { assistantMessageId = mid }
        if let ts = s.createdAt { createdAt = ts }
        ensureStepStarted()
    }

    private mutating func handleText(_ t: String) {
        ensureStepStarted()
        textBuffer.append(t)
    }

    private mutating func handleReasoning(_ r: ChatMessageStreamFrame.ReasoningFrame) {
        ensureStepStarted()
        reasoningBuffer.append(r.text)
    }

    private mutating func addSource(_ s: ChatMessage.Source) { sources.append(s) }

    private mutating func handleToolStart(_ t: ChatMessageStreamFrame.ToolCallStartFrame) {
        ensureStepStarted()
        upsertTool(t.toolCallId) { acc in
            if let name = t.toolName { acc.toolName = name }
            if let args = t.args { acc.args = args }
            acc.state = .partialCall
        }
    }

    private mutating func handleToolDelta(_ d: ChatMessageStreamFrame.ToolCallDeltaFrame) {
        ensureStepStarted()
        upsertTool(d.toolCallId) { acc in
            if let delta = d.argsDelta { acc.args = delta }
            acc.state = .partialCall
        }
    }

    private mutating func handleToolCall(_ t: ChatMessageStreamFrame.ToolCallFrame) {
        ensureStepStarted()
        upsertTool(t.toolCallId) { acc in
            acc.toolName = t.toolName
            acc.args = t.args
            acc.state = .call
        }
    }

    private mutating func handleToolResult(_ r: ChatMessageStreamFrame.ToolResultFrame) {
        upsertTool(r.toolCallId) { acc in
            acc.result = r.result
            acc.state = .result
        }
    }

    private mutating func ensureStepStarted() { if !hasStepStart { hasStepStart = true } }

    private mutating func upsertTool(_ id: String, _ apply: (inout PendingToolInvocation) -> Void) {
        var acc =
            toolStates[id]
            ?? PendingToolInvocation(
                toolCallId: id,
                toolName: "",
                args: nil,
                result: nil,
                state: .partialCall
            )
        apply(&acc)
        if toolStates[id] == nil { toolOrder.append(id) }
        toolStates[id] = acc
    }

    private struct PendingToolInvocation {
        var toolCallId: String
        var toolName: String
        var args: AnyCodable?
        var result: AnyCodable?
        var state: ChatMessage.ToolInvocation.State
    }
}
