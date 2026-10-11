import SwiftUI
import SwiftData

/// Chat with the AI about one song. Replies can fill the song's tabs:
/// lyrics, title, fusion tags (resolved against the dataset), direction
/// and Suno lyrics. A version is saved before anything is applied, and
/// each applied reply can be undone.
struct SongChatView: View {
    @Bindable var project: SongProject
    @ObservedObject var ai: AIService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var macros = CommandMacroStore.shared
    @AppStorage("anchord.chat.autoApply") private var autoApply = true

    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var isShowingMacros = false
    @State private var isConfirmingClear = false
    @FocusState private var isInputFocused: Bool

    private var palette: CardPalette { CardPalette.forID(project.id) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if project.chatMessages.isEmpty {
                            emptyState
                        }
                        ForEach(project.sortedChat) { message in
                            ChatBubble(
                                message: message,
                                palette: palette,
                                onApply: { Task { await apply(message) } },
                                onUndo: { undo(message) }
                            )
                            .id(message.id)
                        }
                        if ai.isGenerating {
                            TypingIndicator()
                                .id("typing")
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(12)
                                .anchordCard(cornerRadius: 16)
                                .id("error")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: project.chatMessages.count) { scrollToEnd(proxy) }
                .onChange(of: ai.isGenerating) { scrollToEnd(proxy) }
                .onAppear { scrollToEnd(proxy, animated: false) }
            }
            .background(AnchordBackground(palette: palette).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingMacros) {
                MacroEditorView()
            }
            .confirmationDialog("Clear this chat?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear Chat", role: .destructive) {
                    for message in project.chatMessages { modelContext.delete(message) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your song and its versions are kept.")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text("Song Chat")
                    .font(.headline)
                Text(providerLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle(isOn: $autoApply) {
                    Label("Auto-apply Changes", systemImage: "wand.and.rays")
                }
                Button {
                    isShowingMacros = true
                } label: {
                    Label("Command Macros", systemImage: "command")
                }
                Divider()
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("Clear Chat", systemImage: "trash")
                }
                .disabled(project.chatMessages.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Chat options")
        }
    }

    private var providerLabel: String {
        let resolution = ai.resolve(project.aiProviderPreference)
        return resolution.status.isReady ? resolution.kind.displayName : "AI unavailable"
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(palette.gradient)
            Text("Write this song together")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Ask for verses, hooks, a fusion or a full Suno setup. Anchord fills the tabs for you and saves a version first, so you can always undo. Type / for command macros.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(starterPrompts, id: \.self) { starter in
                    Button {
                        draft = starter
                        isInputFocused = true
                    } label: {
                        HStack {
                            Text(starter)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
        .padding(18)
        .anchordCard()
    }

    private var starterPrompts: [String] {
        if project.lyrics.isEmpty {
            return [
                "Write a first verse and chorus about leaving a small town at night",
                "/fusion moody, slow, late-night drive",
                "Give me three song concepts with a title and a hook each",
            ]
        }
        return [
            "/punchup",
            "/full",
            "What's the weakest part of this song and why?",
        ]
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(macroSuggestions) { macro in
                        Button {
                            draft = "/\(macro.trigger) "
                            isInputFocused = true
                        } label: {
                            Text("/\(macro.trigger)")
                                .font(.caption.weight(.semibold).monospaced())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(palette.start.opacity(0.15), in: Capsule())
                                .foregroundStyle(palette.start)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(macro.title)
                    }
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message, or / for a command", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(palette.gradient, in: Circle())
                        .opacity(canSend ? 1 : 0.4)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.bar)
    }

    private var macroSuggestions: [CommandMacro] {
        if draft.hasPrefix("/"), !draft.contains(" ") {
            return macros.suggestions(for: String(draft.dropFirst()))
        }
        return macros.macros
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ai.isGenerating
    }

    // MARK: Actions

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !ai.isGenerating else { return }
        let expanded = macros.expand(text, project: project) ?? text
        let history = project.sortedChat

        let userMessage = ChatMessage(role: "user", text: text)
        modelContext.insert(userMessage)
        userMessage.project = project
        draft = ""
        errorMessage = nil

        Task {
            do {
                let reply = try await ai.chat(expanded, project: project, history: history, preference: project.aiProviderPreference)
                let message = ChatMessage(role: "assistant", text: reply)
                modelContext.insert(message)
                message.project = project
                if autoApply, !AssistantReply.parse(reply).blocks.isEmpty {
                    await apply(message)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ message: ChatMessage) async {
        let reply = AssistantReply.parse(message.text)
        guard !reply.blocks.isEmpty, message.appliedVersionNumber == nil else { return }
        let version = project.saveVersion(label: "Before chat edit", in: modelContext)
        let result = await SongAssistant.apply(reply.blocks, to: project)
        message.appliedVersionNumber = version.number
        message.appliedSummary = result.summary
    }

    private func undo(_ message: ChatMessage) {
        guard let number = message.appliedVersionNumber,
              let version = project.versions.first(where: { $0.number == number }) else { return }
        project.restore(version)
        message.appliedVersionNumber = nil
        message.appliedSummary = "Undone"
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable? = ai.isGenerating ? AnyHashable("typing") : project.sortedChat.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

// MARK: - Bubbles

private struct ChatBubble: View {
    let message: ChatMessage
    let palette: CardPalette
    let onApply: () -> Void
    let onUndo: () -> Void

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            assistantBubble
        }
    }

    private var assistantBubble: some View {
        let reply = AssistantReply.parse(message.text)
        return VStack(alignment: .leading, spacing: 10) {
            if !reply.prose.isEmpty {
                Text(markdown(reply.prose))
                    .font(.body)
                    .textSelection(.enabled)
            }
            ForEach(reply.blocks) { block in
                BlockCard(block: block, palette: palette)
            }
            if !reply.blocks.isEmpty {
                applyFooter
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .anchordCard(cornerRadius: 20)
        .padding(.trailing, 24)
    }

    @ViewBuilder
    private var applyFooter: some View {
        if message.appliedVersionNumber != nil {
            HStack(alignment: .top) {
                Label(message.appliedSummary ?? "Applied", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Button("Undo", action: onUndo)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            HStack {
                if message.appliedSummary == "Undone" {
                    Text("Undone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onApply) {
                    Label("Apply to Song", systemImage: "square.and.arrow.down.on.square")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.start)
                .controlSize(.small)
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct BlockCard: View {
    let block: ReplyBlock
    let palette: CardPalette
    @State private var isExpanded = false

    private var lines: [String] { block.content.components(separatedBy: .newlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(block.kind.displayName, systemImage: block.kind.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.start)
                Spacer()
                if lines.count > 6 {
                    Button(isExpanded ? "Less" : "More") { isExpanded.toggle() }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            Text(isExpanded ? block.content : lines.prefix(6).joined(separator: "\n"))
                .font(block.kind == .lyrics || block.kind == .sunoLyrics ? .callout : .footnote)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(0.35 + 0.65 * abs(sin(phase + Double(index) * 0.8)))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .anchordCard(cornerRadius: 18)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
        }
        .accessibilityLabel("Anchord is writing")
    }
}
