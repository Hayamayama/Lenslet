//
//  LensletResult.swift
//  Lenslet
//
//  Created by Kris on 2026/6/23.
//


import Foundation

struct LensletMemory: Identifiable, Codable, Hashable {
    /// Stable memory identifier. Usually the markdown filename without extension.
    let id: String

    /// Absolute markdown file path on disk.
    let path: String

    /// Display title shown in browser/search UI.
    let title: String

    /// Short preview text for list cards.
    let preview: String

    /// Optional generated summary.
    let summary: String?

    /// Optional original OCR/source text.
    let originalText: String?

    /// Optional source label, such as screen_capture, pdf, clipboard.
    let source: String?

    /// Optional creation date parsed from memory markdown metadata.
    let createdAt: Date?
}


struct LensletResult: Codable {

    /// Overall pipeline status returned by Python.
    let status: String

    /// OCR text extracted from the captured image.
    let ocr: String?

    /// LLM-generated summary.
    let summary: String?

    /// Markdown file written into the memory store.
    let memory_path: String?

    /// Related memories returned from vector search.
    let related: [RelatedMemory]?

    /// Human-readable error returned by the Python pipeline.
    /// This allows the UI to display failures without relying on stderr.
    let error: String?

    var isSuccess: Bool {
        status.lowercased() == "ok" || status.lowercased() == "success"
    }
}


struct RelatedMemory: Codable, Hashable {
    let id: String
    let path: String
    let distance: Double
    let text: String

    var asLensletMemory: LensletMemory {
        let url = URL(fileURLWithPath: path)
        let filename = url.deletingPathExtension().lastPathComponent
        let title = filename.isEmpty ? id : filename

        return LensletMemory(
            id: id,
            path: path,
            title: title,
            preview: text,
            summary: nil,
            originalText: text,
            source: nil,
            createdAt: nil
        )
    }
}
