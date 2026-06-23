//
//  LensletApp.swift
//  Lenslet
//
//  Created by Kris on 2026/6/23.
//
import SwiftUI

struct ResultView: View {
    let result: LensletResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                summarySection

                Divider()

                relatedSection
            }
            .padding(24)
        }
        .frame(width: 680, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lenslet")
                .font(.largeTitle)
                .bold()

            if let memoryPath = result.memory_path {
                Text(URL(fileURLWithPath: memoryPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)

            if let summary = result.summary {
                markdownText(summary)
                    .textSelection(.enabled)
            } else {
                Text("No summary returned.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Memories")
                .font(.headline)

            let related = result.related ?? []

            if related.isEmpty {
                Text("No related memories yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(related, id: \.id) { memory in
                    relatedCard(memory)
                }
            }
        }
    }

    private func relatedCard(_ memory: RelatedMemory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(memoryTitle(memory))
                        .font(.headline)

                    Text(URL(fileURLWithPath: memory.path).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(matchLabel(memory.distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(cleanPreview(memory.text))
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func markdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(markdown: raw) {
            return Text(attributed)
        }

        return Text(raw)
    }

    private func memoryTitle(_ memory: RelatedMemory) -> String {
        let filename = URL(fileURLWithPath: memory.path).deletingPathExtension().lastPathComponent

        if filename.isEmpty {
            return memory.id
        }

        return filename
    }

    private func matchLabel(_ distance: Double) -> String {
        let score = max(0, min(100, Int((1.0 - distance) * 100)))
        return "\(score)% match"
    }

    private func cleanPreview(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "---", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
