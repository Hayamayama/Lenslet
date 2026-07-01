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


struct PdfIngestResult: Codable {

    /// Overall ingest status returned by Python.
    let status: String

    /// Absolute source PDF path on disk.
    let path: String?

    /// Source PDF filename.
    let filename: String?

    /// Optional course or project label passed from Swift.
    let course: String?

    /// Number of vector chunks stored in Chroma.
    let chunks_stored: Int?

    /// True when the PDF produced no text chunks and likely needs OCR fallback.
    let needs_ocr: Bool?

    /// Human-readable error returned by Python.
    let error: String?

    var isSuccess: Bool {
        status.lowercased() == "ok" || status.lowercased() == "success"
    }

    var displayMessage: String {
        if isSuccess {
            let name = filename ?? "PDF"
            let chunks = chunks_stored ?? 0
            let ocrNote = needs_ocr == true ? " Needs OCR fallback." : ""
            return "Stored \(chunks) chunks from \(name).\(ocrNote)"
        }

        return error ?? "PDF ingest failed."
    }
}


struct LensletQueryResult: Codable {

    /// Original question sent to Lenslet memory.
    let question: String

    /// Grounded answer generated from retrieved memory chunks.
    let answer: String

    /// Source chunks used to answer the question.
    let sources: [LensletQuerySource]
}


struct LensletQuerySource: Codable, Hashable, Identifiable {

    /// Stable id returned from Chroma / vector memory.
    let id: String

    /// Absolute source path when available.
    let path: String?

    /// Source type, such as screenshot, pdf, document.
    let source_type: String?

    /// Source filename for PDF/document chunks.
    let filename: String?

    /// Page number for PDF/document chunks.
    let page: Int?

    /// Chunk index within the source document/page.
    let chunk_index: Int?

    /// Vector distance returned by Chroma.
    let distance: Double?

    /// Preview text from the retrieved source chunk.
    let text: String?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case source_type
        case filename
        case page
        case chunk_index
        case distance
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        path = try container.decodeFlexibleString(forKey: .path)
        source_type = try container.decodeFlexibleString(forKey: .source_type)
        filename = try container.decodeFlexibleString(forKey: .filename)
        page = try container.decodeFlexibleInt(forKey: .page)
        chunk_index = try container.decodeFlexibleInt(forKey: .chunk_index)
        distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        text = try container.decodeFlexibleString(forKey: .text)
    }

    var displayTitle: String {
        if let filename, !filename.isEmpty {
            return filename
        }

        if let path, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return source_type ?? "Lenslet Memory"
    }

    var displayLocation: String {
        var parts: [String] = []

        if let page {
            parts.append("page \(page)")
        }

        if let chunk_index {
            parts.append("chunk \(chunk_index)")
        }

        if parts.isEmpty {
            return source_type ?? "memory"
        }

        return parts.joined(separator: ", ")
    }
}


struct RelatedMemory: Codable, Hashable {
    let id: String
    let path: String
    let distance: Double
    let text: String
    let source_type: String?
    let filename: String?
    let page: Int?
    let chunk_index: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case distance
        case text
        case source_type
        case filename
        case page
        case chunk_index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        path = try container.decodeFlexibleString(forKey: .path) ?? ""
        distance = try container.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        text = try container.decodeFlexibleString(forKey: .text) ?? ""
        source_type = try container.decodeFlexibleString(forKey: .source_type)
        filename = try container.decodeFlexibleString(forKey: .filename)
        page = try container.decodeFlexibleInt(forKey: .page)
        chunk_index = try container.decodeFlexibleInt(forKey: .chunk_index)
    }

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
            source: source_type,
            createdAt: nil
        )
    }
}

extension KeyedDecodingContainer {

    func decodeFlexibleString(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : value
        }

        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }

        if let value = try decodeIfPresent(Bool.self, forKey: key) {
            return String(value)
        }

        return nil
    }

    func decodeFlexibleInt(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            return Int(trimmed)
        }

        return nil
    }
}
