import SwiftUI
import AppKit

// MARK: - Chat message model

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Main Window

struct MainWindowView: View {
    @State private var memories: [LensletMemory] = []
    @State private var selectedMemory: LensletMemory?
    @State private var searchText = ""
    @State private var relatedMemories: [RelatedMemory] = []
    @State private var isLoadingRelated = false

    @State private var chatMessages: [ChatMessage] = []
    @State private var chatInput = ""
    @State private var isChatLoading = false
    @State private var chatPanelOpen = false

    private let store = MemoryStore()

    private var filteredMemories: [LensletMemory] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return memories }
        return memories.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.preview.localizedCaseInsensitiveContains(q) ||
            ($0.summary?.localizedCaseInsensitiveContains(q) ?? false) ||
            ($0.originalText?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var groupedMemories: [(label: String, memories: [LensletMemory])] {
        let now = Date()
        let calendar = Calendar.current
        var buckets: [String: [LensletMemory]] = [:]
        let order = ["Today", "Yesterday", "This Week", "Earlier"]

        for memory in filteredMemories {
            let date = memory.createdAt ?? .distantPast
            let label: String
            if calendar.isDateInToday(date) {
                label = "Today"
            } else if calendar.isDateInYesterday(date) {
                label = "Yesterday"
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
                label = "This Week"
            } else {
                label = "Earlier"
            }
            buckets[label, default: []].append(memory)
        }

        return order.compactMap { label in
            guard let items = buckets[label], !items.isEmpty else { return nil }
            return (label: label, memories: items)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { reloadMemories() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Reload memories")
                    }
                }
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if let memory = selectedMemory {
                        MemoryDetailView(
                            memory: memory,
                            relatedMemories: relatedMemories,
                            isLoadingRelated: isLoadingRelated,
                            onSelectRelated: { path in
                                selectedMemory = memories.first { $0.path == path }
                            }
                        )
                        .id(memory.id)
                    } else {
                        emptyDetail
                    }
                }
                .frame(maxHeight: .infinity)

                chatPanel
            }
        }
        .onAppear { reloadMemories() }
        .onReceive(NotificationCenter.default.publisher(for: .lensletMemoryAdded)) { _ in
            reloadMemories()
        }
        .onChange(of: selectedMemory) { _, newMemory in
            loadRelated(for: newMemory)
        }
    }

    // MARK: Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            memoryList
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var memoryList: some View {
        Group {
            if filteredMemories.isEmpty {
                emptySidebar
            } else {
                List(selection: $selectedMemory) {
                    ForEach(groupedMemories, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.memories) { memory in
                                MemoryRowView(memory: memory)
                                    .tag(memory)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 8) {
            Text(searchText.isEmpty ? "No memories yet." : "No results.")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Capture something to get started.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Empty detail

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a memory")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Your captured memories will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Chat panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            Divider()

            // Header — always visible, toggles panel
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    chatPanelOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "message.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Ask Lenslet")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: chatPanelOpen ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .windowBackgroundColor))

            if chatPanelOpen {
                Divider()
                chatMessageList
                Divider()
                chatInputBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var chatMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chatMessages) { msg in
                        chatBubble(msg)
                    }
                    if isChatLoading {
                        chatLoadingBubble
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .frame(height: 180)
            .onChange(of: chatMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isChatLoading) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            Text(message.text)
                .font(.callout)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    message.role == .user
                        ? Color.accentColor
                        : Color(nsColor: .controlBackgroundColor)
                )
                .foregroundStyle(
                    message.role == .user
                        ? Color.white
                        : Color.primary
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 12)
                )

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var chatLoadingBubble: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Searching memory…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Lenslet…", text: $chatInput)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { sendChatMessage() }

            Button(action: sendChatMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(
                        chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChatLoading
                            ? Color.secondary
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChatLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Data

    private func reloadMemories() {
        let loaded = store.loadMemories()
        memories = loaded
        if let sel = selectedMemory, !loaded.contains(where: { $0.id == sel.id }) {
            selectedMemory = nil
        }
        if selectedMemory == nil {
            selectedMemory = loaded.first
        }
    }

    private func loadRelated(for memory: LensletMemory?) {
        guard let memory else {
            relatedMemories = []
            return
        }
        let query = [memory.summary, memory.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else {
            relatedMemories = []
            return
        }
        isLoadingRelated = true
        relatedMemories = []
        LensletRuntime.shared.searchRelated(query: query, topK: 5) { results in
            relatedMemories = results.filter { $0.id != memory.id }
            isLoadingRelated = false
        }
    }

    private func sendChatMessage() {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isChatLoading else { return }

        chatInput = ""
        chatMessages.append(ChatMessage(role: .user, text: question))
        isChatLoading = true

        if !chatPanelOpen {
            withAnimation(.easeInOut(duration: 0.18)) { chatPanelOpen = true }
        }

        LensletRuntime.shared.runChatQuery(question: question) { result in
            isChatLoading = false
            switch result {
            case .success(let response):
                chatMessages.append(ChatMessage(role: .assistant, text: response.answer))
            case .failure:
                chatMessages.append(ChatMessage(role: .assistant, text: "Something went wrong. Check that Ollama is running."))
            }
        }
    }
}

// MARK: - Memory Row

struct MemoryRowView: View {
    let memory: LensletMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(2)

            Text(memory.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let source = memory.source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Memory Detail

struct MemoryDetailView: View {
    let memory: LensletMemory
    var relatedMemories: [RelatedMemory] = []
    var isLoadingRelated: Bool = false
    var onSelectRelated: ((String) -> Void)? = nil

    private var formattedDate: String {
        guard let date = memory.createdAt else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                actionBar
                Divider()
                if let summary = memory.summary {
                    contentSection("Summary", text: summary)
                }
                if let original = memory.originalText {
                    contentSection("Original Capture", text: original)
                }
                relatedSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memory.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .textSelection(.enabled)

            HStack(spacing: 14) {
                if !formattedDate.isEmpty {
                    Label(formattedDate, systemImage: "calendar")
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
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: memory.path))
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: memory.path)])
            }
            if memory.summary != nil {
                Button("Copy Summary") {
                    guard let summary = memory.summary else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func contentSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(cleaned(text))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)

            Text("Related Memories")
                .font(.headline)
                .foregroundStyle(.secondary)

            if isLoadingRelated {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if relatedMemories.isEmpty {
                Text("No related memories found.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(relatedMemories, id: \.id) { related in
                    RelatedMemoryCard(related: related, onSelect: {
                        if !related.path.isEmpty {
                            onSelectRelated?(related.path)
                        }
                    })
                }
            }
        }
    }

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "---", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Related Memory Card

struct RelatedMemoryCard: View {
    let related: RelatedMemory
    let onSelect: () -> Void

    private var title: String {
        if let filename = related.filename, !filename.isEmpty { return filename }
        let url = URL(fileURLWithPath: related.path)
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? related.id : stem
    }

    private var matchPercent: Int {
        max(0, min(100, Int((1.0 - related.distance) * 100)))
    }

    private var sourceLabel: String {
        switch related.source_type {
        case "pdf", "document": return "PDF"
        default: return "Capture"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(matchPercent)% match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text(sourceLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let page = related.page {
                        Text("p.\(page)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !related.text.isEmpty {
                    Text(related.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification

extension NSNotification.Name {
    static let lensletMemoryAdded = NSNotification.Name("lensletMemoryAdded")
}
