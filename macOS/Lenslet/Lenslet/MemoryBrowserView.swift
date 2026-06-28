//
//  MemoryBrowserView.swift
//  Lenslet
//
//  Created by Kris on 2026/6/28.
//

import SwiftUI
import AppKit

struct MemoryBrowserView: View {
    @State private var memories: [LensletMemory] = []
    @State private var selectedMemory: LensletMemory?
    @State private var searchText = ""

    private let store = MemoryStore()

    private var filteredMemories: [LensletMemory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return memories
        }

        return memories.filter { memory in
            memory.title.localizedCaseInsensitiveContains(query) ||
            memory.preview.localizedCaseInsensitiveContains(query) ||
            (memory.summary?.localizedCaseInsensitiveContains(query) ?? false) ||
            (memory.originalText?.localizedCaseInsensitiveContains(query) ?? false) ||
            (memory.source?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 920, height: 640)
        .onAppear {
            reloadMemories()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Memories")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    reloadMemories()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload memories")
            }

            TextField("Search memories", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredMemories.isEmpty {
                emptySidebarState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredMemories) { memory in
                            memoryRow(memory)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptySidebarState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No memories yet." : "No matching memories.")
                .font(.headline)

            Text("Capture something first, then come back here.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 16)
    }

    private func memoryRow(_ memory: LensletMemory) -> some View {
        Button {
            selectedMemory = memory
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(memory.title)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer()

                    if let createdAt = memory.createdAt {
                        Text(shortDateFormatter.string(from: createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(memory.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                if let source = memory.source {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(rowBackground(memory))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(_ memory: LensletMemory) -> Color {
        if selectedMemory?.id == memory.id {
            return Color.accentColor.opacity(0.18)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var detail: some View {
        Group {
            if let selectedMemory {
                memoryDetail(selectedMemory)
            } else {
                emptyDetailState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyDetailState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Select a memory")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Saved Lenslet memories will appear here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func memoryDetail(_ memory: LensletMemory) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        if let createdAt = memory.createdAt {
                            Label(detailDateFormatter.string(from: createdAt), systemImage: "calendar")
                        }

                        if let source = memory.source {
                            Label(source, systemImage: "tray.full")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(memory.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Open Memory") {
                        openMemory(memory)
                    }

                    Button("Reveal in Finder") {
                        revealMemory(memory)
                    }

                    Button("Copy Summary") {
                        copySummary(memory)
                    }
                    .disabled(memory.summary == nil)

                    Spacer()
                }

                if let summary = memory.summary {
                    detailSection(title: "Summary", text: summary)
                }

                if let originalText = memory.originalText {
                    detailSection(title: "Original Capture", text: originalText)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(cleaned(text))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reloadMemories() {
        memories = store.loadMemories()

        if let selectedMemory,
           !memories.contains(where: { $0.id == selectedMemory.id }) {
            self.selectedMemory = nil
        }

        if selectedMemory == nil {
            self.selectedMemory = memories.first
        }
    }

    private func openMemory(_ memory: LensletMemory) {
        NSWorkspace.shared.open(URL(fileURLWithPath: memory.path))
    }

    private func revealMemory(_ memory: LensletMemory) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: memory.path)
        ])
    }

    private func copySummary(_ memory: LensletMemory) {
        guard let summary = memory.summary else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "---", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }

    private var detailDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}
