import SwiftUI
import SwiftData

/// The song workspace: write → analyze → build Prompt DNA → generate and
/// refine Suno POS/NEG/LYRICS → save versions, all without leaving the
/// song. The dataset-driven Fusion Builder is the prompt engine; AI
/// features work on top of its output and Anchord's measurements.
struct SongEditorView: View {
    @Bindable var project: SongProject
    @Environment(\.modelContext) private var modelContext
    @StateObject private var ai = AIService()
    @ObservedObject private var lyricPreferences = LyricPreferencesStore.shared

    @State private var selectedTab: EditorTab = .lyrics
    @State private var isShowingSettings = false
    @State private var isShowingFusionBuilder = false
    @State private var isShowingVersions = false
    @State private var isShowingLyricPreferences = false
    @State private var rewriteTarget: LineAnalysis?
    @State private var reviewNotes = ""
    @State private var errorMessage: String?
    @State private var notice: String?

    enum EditorTab: String, CaseIterable, Identifiable {
        case lyrics = "Lyrics"
        case analysis = "Analysis"
        case prompt = "Prompt"
        case suno = "Suno"

        var id: String { rawValue }
    }

    private var analysis: LyricAnalysis {
        CadenceAnalyzer(preferences: lyricPreferences.preferences).analyzeSong(project.lyrics)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(EditorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedTab {
            case .lyrics: lyricsTab
            case .analysis: analysisTab
            case .prompt: promptTab
            case .suno: sunoTab
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { noticeBanner }
        .sheet(isPresented: $isShowingSettings) {
            ModelManagerView()
        }
        .sheet(isPresented: $isShowingFusionBuilder) {
            FusionBuilderView(project: project)
        }
        .sheet(isPresented: $isShowingVersions) {
            SongVersionsView(project: project)
        }
        .sheet(isPresented: $isShowingLyricPreferences) {
            LyricPreferencesView()
        }
        .sheet(item: $rewriteTarget) { line in
            LineRewriteView(line: line, song: analysis, preference: project.aiProviderPreference, ai: ai) { replacement in
                project.lyrics = LyricsEditing.replacingLine(at: line.id, in: project.lyrics, with: replacement)
            }
        }
        .alert("AI Unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("AI Settings") { isShowingSettings = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: project.lyrics) { project.updatedAt = .now }
        .onChange(of: project.title) { project.updatedAt = .now }
        .onChange(of: project.soundPrompt) { project.updatedAt = .now }
        .onChange(of: project.negativePrompt) { project.updatedAt = .now }
        .onChange(of: project.sunoLyrics) { project.updatedAt = .now }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if ai.isGenerating {
                ProgressView()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    saveVersion(label: nil)
                } label: {
                    Label("Save Version", systemImage: "clock.badge.checkmark")
                }
                Button {
                    isShowingVersions = true
                } label: {
                    Label("Version History (\(project.versions.count))", systemImage: "clock.arrow.circlepath")
                }

                Divider()

                Button {
                    isShowingLyricPreferences = true
                } label: {
                    Label("Lyric Preferences", systemImage: "slider.horizontal.3")
                }
                Picker(selection: $project.aiProviderPreference) {
                    ForEach(AIProviderPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                } label: {
                    Label("AI Provider", systemImage: "cpu")
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Label("AI Settings", systemImage: "gearshape")
                }

                Divider()

                ShareLink(item: exportText) {
                    Label("Share Suno Output", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Song options")
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice {
            Text(notice)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { self.notice = nil }
                }
        }
    }

    // MARK: Lyrics

    private var lyricsTab: some View {
        let lines = analysis.lines
        return VStack(alignment: .leading, spacing: 0) {
            TextField("Song title", text: $project.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 4)

            TextEditor(text: $project.lyrics)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if project.lyrics.isEmpty {
                        Text("Write your lyrics here.\nLeave a blank line between sections, or use tags like [Verse] and [Chorus].")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }

            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap a line to rewrite it")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lines) { line in
                                Button {
                                    rewriteTarget = line
                                } label: {
                                    CadenceChip(line: line)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                }
                .padding(.top, 6)
                .background(.bar)
            }
        }
    }

    // MARK: Analysis

    private var analysisTab: some View {
        let song = analysis
        return List {
            if song.lines.isEmpty {
                Section {
                    Text("Write some lyrics to see cadence, stress and rhyme analysis.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    HStack {
                        StatCell(value: "\(song.lines.count)", label: "Lines")
                        StatCell(value: "\(song.totalSyllables)", label: "Syllables")
                        StatCell(value: "\(song.outOfPocketLines.count)", label: "Off-pocket")
                    }
                    if !song.bannedHits.isEmpty || !song.clicheHits.isEmpty {
                        HStack {
                            StatCell(value: "\(song.bannedHits.count)", label: "Banned words")
                            StatCell(value: "\(song.clicheHits.count)", label: "Clichés")
                        }
                    }
                    Button {
                        isShowingLyricPreferences = true
                    } label: {
                        Label("Lyric Preferences", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Syllables, stress and rhyme are estimated from spelling rules, not a pronunciation dictionary. Unusual words may be off by one.")
                }

                ForEach(song.stanzas) { stanza in
                    Section {
                        ForEach(song.lines.filter { $0.stanza == stanza.id }) { line in
                            Button {
                                rewriteTarget = line
                            } label: {
                                LineAnalysisRow(line: line)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(stanza.label ?? "Section \(stanza.id + 1)")
                            Spacer()
                            Text("avg \(stanza.averageSyllables, specifier: "%.1f") · \(stanza.scheme)")
                                .font(.caption.monospaced())
                        }
                    }
                }
            }

            Section {
                Button {
                    runAIAnalysis(song)
                } label: {
                    Label("Analyze with AI", systemImage: "sparkles")
                }
                .disabled(project.lyrics.isEmpty || ai.isGenerating)

                if !project.analysisNotes.isEmpty {
                    Text(project.analysisNotes)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            } header: {
                Text("AI Analysis")
            } footer: {
                Text("Uses \(ai.resolve(project.aiProviderPreference).kind.displayName.lowercased()) with the measurements above as constraints.")
            }
        }
    }

    // MARK: Prompt DNA

    private var promptTab: some View {
        let dna = project.promptDNA
        return Form {
            Section {
                Button {
                    isShowingFusionBuilder = true
                } label: {
                    Label(
                        dna.selectedTags.isEmpty ? "Build with Fusion Engine" : "Edit Fusion",
                        systemImage: "wand.and.stars"
                    )
                }
                if !dna.selectedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(dna.mode.displayName) · \(dna.selectedTags.count) tags")
                            .font(.caption.bold())
                        FlowLayout(spacing: 6) {
                            ForEach(dna.selectedTags) { tag in
                                Label(tag.name, systemImage: tag.category.symbolName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Dataset Fusion")
            } footer: {
                Text("Tags come from 215,240 real Suno tags mined from 659,788 songs, picked by rarity and category.")
            }

            Section {
                Picker("Energy", selection: intentEnergy) {
                    ForEach(EnergyLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                TextField("Vocals (e.g. breathy alto, gang shouts)", text: intentText(\.vocals), axis: .vertical)
                TextField("Mood", text: intentText(\.mood), axis: .vertical)
                TextField("Instrumentation", text: intentText(\.instrumentation), axis: .vertical)
                TextField("Production", text: intentText(\.production), axis: .vertical)
                TextField("Mix / master", text: intentText(\.mixing), axis: .vertical)
                TextField("Performance", text: intentText(\.performance), axis: .vertical)
                TextField("Avoid (added to NEG)", text: intentText(\.avoid), axis: .vertical)
            } header: {
                Text("Your Direction")
            } footer: {
                Text("Added to the dataset prompt as a short direction line. Leave anything blank to skip it.")
            }

            Section {
                Button {
                    generateFromDNA()
                } label: {
                    Label("Generate POS & NEG", systemImage: "text.badge.star")
                }
                .disabled(dna.selectedTags.isEmpty && dna.intent.isEmpty)

                Button {
                    reviewPrompt()
                } label: {
                    Label("Review Prompt with AI", systemImage: "sparkles")
                }
                .disabled(project.soundPrompt.isEmpty || ai.isGenerating)

                if !reviewNotes.isEmpty {
                    Text(reviewNotes)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Generating replaces POS and NEG. The previous text is saved as a version first.")
            }
        }
    }

    // MARK: Suno output

    private var sunoTab: some View {
        Form {
            OutputSection(
                title: "Style (POS)",
                text: $project.soundPrompt,
                limit: PromptDNAComposer.positiveLimit,
                minHeight: 160,
                onCopy: { copy(project.soundPrompt, "Style copied") }
            )
            OutputSection(
                title: "Exclude (NEG)",
                text: $project.negativePrompt,
                limit: PromptDNAComposer.negativeLimit,
                minHeight: 100,
                onCopy: { copy(project.negativePrompt, "Exclusions copied") }
            )
            Section {
                TextEditor(text: $project.sunoLyrics)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 220)
                HStack {
                    Button {
                        buildSunoLyrics()
                    } label: {
                        Label(project.sunoLyrics.isEmpty ? "Build from Draft" : "Rebuild from Draft", systemImage: "text.alignleft")
                    }
                    .disabled(project.lyrics.isEmpty)
                    Spacer()
                    Button {
                        copy(project.sunoLyrics, "Lyrics copied")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(project.sunoLyrics.isEmpty)
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Keeps your [Section] tags, or infers Verse/Chorus from repeated stanzas. Edit freely; your draft on the Lyrics tab is never changed.")
            }
        }
    }

    // MARK: Actions

    private func saveVersion(label: String?) {
        let version = project.saveVersion(label: label, in: modelContext)
        show("Saved \(version.displayName)")
    }

    private func generateFromDNA() {
        if !project.soundPrompt.isEmpty || !project.negativePrompt.isEmpty {
            project.saveVersion(label: "Before regenerate", in: modelContext)
        }
        let output = PromptDNAComposer.compose(project.promptDNA)
        project.soundPrompt = output.positive
        project.negativePrompt = output.negative
        if let genre = project.promptDNA.selectedTags.first(where: { $0.category == .genre || $0.category == .subgenre }) {
            project.genre = genre.name
        }
        selectedTab = .suno
        show("Generated from Prompt DNA")
    }

    private func buildSunoLyrics() {
        if !project.sunoLyrics.isEmpty {
            project.saveVersion(label: "Before lyrics rebuild", in: modelContext)
        }
        project.sunoLyrics = SunoLyricsFormatter.format(project.lyrics)
    }

    private func runAIAnalysis(_ song: LyricAnalysis) {
        Task {
            do {
                project.analysisNotes = try await ai.analyzeLyrics(project.lyrics, measurements: song, preference: project.aiProviderPreference)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reviewPrompt() {
        Task {
            do {
                reviewNotes = try await ai.reviewPrompt(
                    positive: project.soundPrompt,
                    negative: project.negativePrompt,
                    dna: project.promptDNA,
                    preference: project.aiProviderPreference
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copy(_ text: String, _ message: String) {
        Clipboard.copy(text)
        show(message)
    }

    private func show(_ message: String) {
        withAnimation { notice = message }
    }

    private var exportText: String {
        """
        \(project.title)

        STYLE (POS):
        \(project.soundPrompt)

        EXCLUDE (NEG):
        \(project.negativePrompt)

        LYRICS:
        \(project.sunoLyrics.isEmpty ? SunoLyricsFormatter.format(project.lyrics) : project.sunoLyrics)
        """
    }

    // MARK: Intent bindings

    private func intentText(_ keyPath: WritableKeyPath<PromptIntent, String>) -> Binding<String> {
        Binding(
            get: { project.promptDNA.intent[keyPath: keyPath] },
            set: { newValue in
                var dna = project.promptDNA
                dna.intent[keyPath: keyPath] = newValue
                project.promptDNA = dna
                project.updatedAt = .now
            }
        )
    }

    private var intentEnergy: Binding<EnergyLevel> {
        Binding(
            get: { project.promptDNA.intent.energy },
            set: { newValue in
                var dna = project.promptDNA
                dna.intent.energy = newValue
                project.promptDNA = dna
                project.updatedAt = .now
            }
        )
    }
}

// MARK: - Components

private struct CadenceChip: View {
    let line: LineAnalysis

    var body: some View {
        HStack(spacing: 4) {
            Text("\(line.id + 1)")
                .foregroundStyle(.secondary)
            Text("\(line.syllableCount)")
                .fontWeight(.semibold)
            if let letter = line.rhymeLetter {
                Text(letter)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipColor, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Line \(line.id + 1), \(line.syllableCount) syllables\(line.rhymeLetter.map { ", rhyme \($0)" } ?? "")")
        .accessibilityHint("Opens line rewrite")
    }

    private var chipColor: Color {
        if !line.bannedTerms.isEmpty { return Color.red.opacity(0.18) }
        if line.isOutOfPocket || line.isOutsideTarget || !line.cliches.isEmpty { return Color.orange.opacity(0.18) }
        return Color(.secondarySystemBackground)
    }
}

private struct LineAnalysisRow: View {
    let line: LineAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.text)
                    .font(.callout)
                Spacer(minLength: 8)
                Text("\(line.syllableCount)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(line.isOutOfPocket || line.isOutsideTarget ? Color.orange : Color.primary)
            }
            HStack(spacing: 10) {
                Text(line.stressPattern)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let letter = line.rhymeLetter {
                    Text("\(letter) · \(line.rhymeKind?.rawValue ?? "")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                if line.isOutOfPocket {
                    Label(line.deviation > 0 ? "+\(Int(line.deviation.rounded()))" : "\(Int(line.deviation.rounded()))", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if !line.bannedTerms.isEmpty {
                Label("Banned: \(line.bannedTerms.joined(separator: ", "))", systemImage: "nosign")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
            if !line.cliches.isEmpty {
                Label("Cliché: \(line.cliches.joined(separator: ", "))", systemImage: "exclamationmark.bubble")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if line.isOutsideTarget {
                Label("Outside your syllable target", systemImage: "ruler")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !line.internalRhymes.isEmpty {
                Text("Internal: " + line.internalRhymes.map { "\($0.first)/\($0.second)" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OutputSection: View {
    let title: String
    @Binding var text: String
    let limit: Int
    let minHeight: CGFloat
    let onCopy: () -> Void

    var body: some View {
        Section {
            TextEditor(text: $text)
                .font(.callout)
                .frame(minHeight: minHeight)
            HStack {
                Text("\(text.count) / \(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(text.count > limit ? .red : .secondary)
                Spacer()
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(text.isEmpty)
            }
        } header: {
            Text(title)
        }
    }
}
