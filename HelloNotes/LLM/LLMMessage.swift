//
//  LLMMessage.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  Provider-agnostic conversation model. Messages are lists of *parts* so one
//  assistant turn can interleave text, reasoning, and tool calls — the shape
//  every modern agent (OpenCode, Pi, Claude Code) converged on. Providers stream
//  `StreamEvent`s that the agent accumulates into these parts.
//

import Foundation

enum LLMRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

/// A model-requested tool invocation.
struct ToolCall: Identifiable, Sendable, Equatable, Codable {
    var id: String            // provider-assigned call id
    var name: String
    var arguments: String     // JSON string (accumulated from streamed fragments)

    var parsedArguments: JSONValue { JSONValue.parse(arguments) ?? .object([:]) }
}

/// The result of running a tool, fed back to the model.
struct ToolResult: Sendable, Equatable, Codable {
    var callID: String
    var output: String
    var isError: Bool = false
}

/// One piece of a message.
enum MessagePart: Sendable, Equatable, Codable {
    case text(String)
    case thinking(String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
}

struct LLMUsage: Sendable, Equatable, Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    static func + (a: LLMUsage, b: LLMUsage) -> LLMUsage {
        LLMUsage(inputTokens: a.inputTokens + b.inputTokens, outputTokens: a.outputTokens + b.outputTokens)
    }
}

struct LLMMessage: Identifiable, Sendable, Equatable, Codable {
    var id: UUID
    var role: LLMRole
    var parts: [MessagePart]
    var usage: LLMUsage?
    var date: Date

    init(id: UUID = UUID(), role: LLMRole, parts: [MessagePart], usage: LLMUsage? = nil, date: Date = Date()) {
        self.id = id
        self.role = role
        self.parts = parts
        self.usage = usage
        self.date = date
    }

    init(role: LLMRole, text: String) {
        self.init(role: role, parts: [.text(text)])
    }

    /// All text parts concatenated (ignores thinking/tool parts).
    var text: String {
        parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
    }

    var toolCalls: [ToolCall] {
        parts.compactMap { if case .toolCall(let c) = $0 { return c } else { return nil } }
    }
}

// MARK: - Streaming

/// Incremental events a provider emits while generating a turn. The agent folds
/// these into the current assistant `LLMMessage`.
enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case toolCallStarted(id: String, name: String)
    case toolCallArgumentsDelta(id: String, fragment: String)
    case toolCallCompleted(id: String)
    case usage(LLMUsage)
    case done(StopReason)
}

enum StopReason: Sendable, Equatable {
    case stop          // natural end of turn
    case toolCalls     // model wants tools run, then continue
    case length        // hit max tokens
    case cancelled
}
