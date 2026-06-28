//
//  LensletResult.swift
//  Lenslet
//
//  Created by Kris on 2026/6/23.
//

import Foundation


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


struct RelatedMemory: Codable {
    
    let id: String
    
    let path: String
    
    let distance: Double
    
    let text: String
}
