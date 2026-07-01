//
//  MemoryStore.swift
//  Lenslet
//
//  Created by Kris on 2026/6/28.
//

import Foundation

struct MemoryStore {
    let memoriesDirectory: URL

    init(memoriesDirectory: URL = MemoryStore.defaultMemoriesDirectory()) {
        self.memoriesDirectory = memoriesDirectory
    }

    func loadMemories() -> [LensletMemory] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: memoriesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { loadMemory(from: $0) }
            .sorted { left, right in
                let leftDate = left.createdAt ?? .distantPast
                let rightDate = right.createdAt ?? .distantPast
                return leftDate > rightDate
            }
    }

    func loadMemory(from fileURL: URL) -> LensletMemory? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let fallbackID = fileURL.deletingPathExtension().lastPathComponent
        let memoryID = metadataValue("Memory ID", in: raw) ?? fallbackID
        let createdAt = parseDate(metadataValue("Created", in: raw)) ?? fileModificationDate(fileURL)
        let source = metadataValue("Source", in: raw)
        let tagsRaw = metadataValue("Tags", in: raw) ?? ""
        let tags = tagsRaw.isEmpty ? [] : tagsRaw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summary = section("Summary", in: raw)
        let originalText = section("Original Capture", in: raw)
        let title = titleForMemory(
            fallbackID: fallbackID,
            summary: summary,
            originalText: originalText
        )
        let preview = previewForMemory(
            summary: summary,
            originalText: originalText
        )
        let sourceApp = metadataValue("Source App", in: raw)
        let sourceURL = metadataValue("Source URL", in: raw)

        return LensletMemory(
            id: memoryID,
            path: fileURL.path,
            title: title,
            preview: preview,
            summary: summary,
            originalText: originalText,
            source: source,
            createdAt: createdAt,
            tags: tags,
            sourceApp: sourceApp,
            sourceURL: sourceURL
        )
    }

    func saveSummary(_ newSummary: String, for memory: LensletMemory) {
        let fileURL = URL(fileURLWithPath: memory.path)
        guard var raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let trimmed = newSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace content between ## Summary and the next ## heading (or end of file)
        if let summaryRange = raw.range(of: #"(?m)^## Summary\s*\n"#, options: .regularExpression) {
            let afterSummary = summaryRange.upperBound
            // Find next section heading
            let searchRange = afterSummary..<raw.endIndex
            if let nextSection = raw.range(of: #"(?m)^## "#, options: .regularExpression, range: searchRange) {
                raw.replaceSubrange(afterSummary..<nextSection.lowerBound, with: "\(trimmed)\n\n")
            } else {
                raw.replaceSubrange(afterSummary..<raw.endIndex, with: "\(trimmed)\n")
            }
        }

        try? raw.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func deleteMemory(_ memory: LensletMemory) {
        let fileURL = URL(fileURLWithPath: memory.path)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func saveTags(_ tags: [String], for memory: LensletMemory) {
        let fileURL = URL(fileURLWithPath: memory.path)
        guard var raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let tagsValue = tags.joined(separator: ", ")
        let newLine = "Tags: \(tagsValue)"

        if let range = raw.range(of: #"(?m)^Tags:.*$"#, options: .regularExpression) {
            raw.replaceSubrange(range, with: newLine)
        } else if let range = raw.range(of: #"(?m)^Memory ID:.*$"#, options: .regularExpression) {
            raw.insert(contentsOf: "\n\(newLine)", at: range.upperBound)
        }

        try? raw.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func defaultMemoriesDirectory() -> URL {
        defaultProjectDirectory().appendingPathComponent("memories", isDirectory: true)
    }

    static func defaultProjectDirectory() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["LENSLET_PROJECT_ROOT"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/04_Research_Dev/VSC/Lenslet", isDirectory: true)
    }

    private func metadataValue(_ key: String, in raw: String) -> String? {
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "\(key):"

            guard trimmed.hasPrefix(prefix) else {
                continue
            }

            let value = trimmed.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return value.isEmpty ? nil : value
        }

        return nil
    }

    private func section(_ title: String, in raw: String) -> String? {
        let lines = raw.components(separatedBy: .newlines)
        let heading = "## \(title)"

        guard let startIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == heading
        }) else {
            return nil
        }

        let contentStart = lines.index(after: startIndex)
        let contentEnd = lines[contentStart...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ")
        }) ?? lines.endIndex

        let content = lines[contentStart..<contentEnd]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return content.isEmpty ? nil : content
    }

    private func titleForMemory(
        fallbackID: String,
        summary: String?,
        originalText: String?
    ) -> String {
        let candidates = [summary, originalText]

        for candidate in candidates {
            guard let firstLine = candidate?
                .components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else {
                continue
            }

            return clipped(firstLine, maxLength: 80)
        }

        return fallbackID
    }

    private func previewForMemory(
        summary: String?,
        originalText: String?
    ) -> String {
        // Skip the first line (already used as title), show subsequent content
        let source = summary?.nilIfBlank ?? originalText?.nilIfBlank ?? ""
        let lines = source.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let body = lines.dropFirst().joined(separator: " ")
        let text = body.nilIfBlank ?? lines.first ?? "No preview available."
        return clipped(text, maxLength: 200)
    }

    private func clipped(_ text: String, maxLength: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "---", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > maxLength else {
            return cleaned
        }

        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
        return String(cleaned[..<endIndex]) + "…"
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return date
        }

        let fractionalFormatter = DateFormatter()
        fractionalFormatter.locale = Locale(identifier: "en_US_POSIX")
        fractionalFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let plainFormatter = DateFormatter()
        plainFormatter.locale = Locale(identifier: "en_US_POSIX")
        plainFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return plainFormatter.date(from: raw)
    }

    private func fileModificationDate(_ fileURL: URL) -> Date? {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
