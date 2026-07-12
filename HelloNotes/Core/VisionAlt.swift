//
//  VisionAlt.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  On-device "vision intelligence" for pasted-image alt text: classifies the
//  image (and OCRs any prominent text) with the Vision framework to produce a
//  short, descriptive alt string. No network, no API key.
//

#if os(macOS)
import Foundation
import Vision
import AppKit

enum VisionAlt {
    /// A short alt-text description of the image at `url`, or `nil` if nothing
    /// confident could be derived.
    static func describe(_ url: URL) async -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        // Prefer readable text (screenshots, diagrams) when present.
        if let text = await recognizedText(cgImage), text.count >= 8 {
            return "Screenshot: \(String(text.prefix(80)))"
        }
        // Otherwise, top classification labels.
        if let labels = await classify(cgImage), !labels.isEmpty {
            return labels.prefix(3).joined(separator: ", ")
        }
        return nil
    }

    private static func classify(_ image: CGImage) async -> [String]? {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                let labels = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.3 }
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(3)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                continuation.resume(returning: Array(labels))
            }
            perform(request, on: image, continuation: continuation, empty: [])
        }
    }

    private static func recognizedText(_ image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: joined.isEmpty ? nil : joined)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            perform(request, on: image, continuation: continuation, empty: nil)
        }
    }

    /// Run a Vision request off the main thread, resuming `continuation` with
    /// `empty` if it throws before its completion handler fires.
    private static func perform<T>(_ request: VNRequest, on image: CGImage,
                                   continuation: CheckedContinuation<T, Never>, empty: T) {
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: empty) }
        }
    }
}
#endif
