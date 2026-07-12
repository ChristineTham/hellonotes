//
//  AssistantModel.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  The chat view-model: owns the conversation, drives a streaming turn against
//  the active provider, and folds `StreamEvent`s into the live assistant message.
//  Phase 1 runs a single turn; the agent tool-loop is layered on in Phase 3
//  (see `runTurn` — the seam where tool execution slots in).
//

import Foundation
import Observation

@MainActor
@Observable
final class AssistantModel {
    let settings: LLMSettings

    var messages: [LLMMessage] = []
    var input: String = ""
    private(set) var isStreaming = false
    private(set) var errorText: String?
    private(set) var totalUsage = LLMUsage()

    /// System prompt for the assistant (vault context is added in later phases).
    var systemPrompt: String =
        "You are the HelloNotes assistant, embedded in a local Markdown notes app. " +
        "Be concise and helpful. Format answers in Markdown."

    private var currentTask: Task<Void, Never>?

    init(settings: LLMSettings) {
        self.settings = settings
    }

    var activeProvider: ProviderKind { settings.activeProvider }
    var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        messages.append(LLMMessage(role: .user, text: text))
        start()
    }

    func stop() {
        currentTask?.cancel()
    }

    func clear() {
        stop()
        messages.removeAll()
        errorText = nil
        totalUsage = LLMUsage()
    }

    private func start() {
        errorText = nil
        isStreaming = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runTurn()
            self.isStreaming = false
        }
    }

    /// One assistant turn: stream the model, folding deltas into a live message.
    /// (Phase 3 adds: if the turn ends in tool calls, run them and loop.)
    private func runTurn() async {
        let kind = settings.activeProvider
        let provider: LLMProvider
        let model: String
        do {
            (provider, model) = try ProviderFactory.make(for: kind, settings: settings)
        } catch {
            errorText = error.localizedDescription
            return
        }

        let context = LLMContext(systemPrompt: systemPrompt, messages: messages, tools: [])
        let options = LLMRequestOptions(temperature: settings.temperature)

        // Live assistant message the deltas accumulate into.
        var assistant = LLMMessage(role: .assistant, parts: [])
        messages.append(assistant)
        let index = messages.count - 1

        func flush() { if messages.indices.contains(index) { messages[index] = assistant } }

        do {
            for try await event in provider.stream(context, model: model, options: options) {
                switch event {
                case .textDelta(let delta):
                    appendText(delta, to: &assistant); flush()
                case .thinkingDelta(let delta):
                    appendThinking(delta, to: &assistant); flush()
                case .usage(let usage):
                    assistant.usage = usage; totalUsage = totalUsage + usage; flush()
                case .toolCallStarted, .toolCallArgumentsDelta, .toolCallCompleted:
                    break  // Phase 3: accumulate + execute tools
                case .done:
                    flush()
                }
            }
        } catch is CancellationError {
            // leave partial text as-is
        } catch {
            errorText = error.localizedDescription
            if assistant.parts.isEmpty, messages.indices.contains(index) {
                messages.remove(at: index)
            }
        }
    }

    // MARK: - Part accumulation

    private func appendText(_ delta: String, to message: inout LLMMessage) {
        if case .text(let existing)? = message.parts.last {
            message.parts[message.parts.count - 1] = .text(existing + delta)
        } else {
            message.parts.append(.text(delta))
        }
    }

    private func appendThinking(_ delta: String, to message: inout LLMMessage) {
        if case .thinking(let existing)? = message.parts.last {
            message.parts[message.parts.count - 1] = .thinking(existing + delta)
        } else {
            message.parts.append(.thinking(delta))
        }
    }
}
