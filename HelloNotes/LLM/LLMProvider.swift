//
//  LLMProvider.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  The single seam every model backend implements. Cloud SDKs (OpenAI-compatible,
//  Anthropic, Gemini) and in-process backends (Apple FoundationModels, MLX) all
//  hide their quirks behind one `stream()` method returning provider-agnostic
//  `StreamEvent`s.
//

import Foundation

/// A tool the model may call, described by a JSON-Schema parameter object.
struct LLMTool: Sendable, Equatable {
    var name: String
    var description: String
    var parameters: JSONValue   // a JSON-Schema `object`
}

/// Everything a provider needs to generate the next assistant turn.
struct LLMContext: Sendable {
    var systemPrompt: String?
    var messages: [LLMMessage]
    var tools: [LLMTool]

    init(systemPrompt: String? = nil, messages: [LLMMessage], tools: [LLMTool] = []) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
    }
}

/// Generation knobs common across providers.
struct LLMRequestOptions: Sendable {
    var temperature: Double?
    var maxTokens: Int?
    init(temperature: Double? = nil, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

protocol LLMProvider: Sendable {
    /// Stream the next assistant turn for `context` using `model`.
    func stream(_ context: LLMContext, model: String, options: LLMRequestOptions) -> AsyncThrowingStream<StreamEvent, Error>
}

extension LLMProvider {
    func stream(_ context: LLMContext, model: String) -> AsyncThrowingStream<StreamEvent, Error> {
        stream(context, model: model, options: LLMRequestOptions())
    }
}

enum LLMError: LocalizedError {
    case missingAPIKey(String)
    case notConfigured(String)
    case unsupported(String)
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): return "No API key set for \(p). Add one in Assistant Settings."
        case .notConfigured(let m): return m
        case .unsupported(let m): return m
        case .provider(let m): return m
        }
    }
}
