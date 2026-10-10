import SwiftUI

struct SongEditorView: View {
    @Bindable var project: SongProject
    @StateObject private var ai = AIService()
    @State private var selectedTab: EditorTab = .lyrics
    @State private var analysis = ""
    @State private var isShowingModels = false
    @State private var isShowingFusionBuilder = false

    private let analyzer = CadenceAnalyzer()

    enum EditorTab: String, CaseIterable {
        case lyrics = "Lyrics"
        case prompt = "Prompt"
        case analysis = "Analysis"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Editor", selection: $selectedTab) {
                ForEach(EditorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .lyrics:
                lyricsEditor
            case .prompt:
                promptEditor
            case .analysis:
                analysisView
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Analyze Lyrics") {
                        Task {
                            analysis = (try? await ai.analyzeLyrics(project.lyrics)) ?? "Analysis unavailable."
                            selectedTab = .analysis
                        }
                    }

                    Button("Model Manager") {
                        isShowingModels = true
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
        .sheet(isPresented: $isShowingModels) {
            ModelManagerView()
        }
        .sheet(isPresented: $isShowingFusionBuilder) {
            FusionBuilderView(project: project)
        }
        .onChange(of: project.lyrics) {
            project.updatedAt = .now
        }
        .onChange(of: project.title) {
            project.updatedAt = .now
        }
    }

    private var lyricsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Song title", text: $project.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .padding(.horizontal)

            TextEditor(text: $project.lyrics)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 8)

            let lines = analyzer.analyze(project.lyrics)

            if !lines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(lines) { line in
                            Text("\(line.syllableCount) syllables")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var promptEditor: some View {
        Form {
            Section {
                Button {
                    isShowingFusionBuilder = true
                } label: {
                    Label(
                        project.promptDNA.selectedTags.isEmpty ? "Build with Fusion Engine" : "Edit Fusion",
                        systemImage: "wand.and.stars"
                    )
                }
                if !project.promptDNA.selectedTags.isEmpty {
                    fusionSummary(project.promptDNA)
                }
            } header: {
                Text("Dataset-Driven Prompt Generator")
            } footer: {
                Text("Randomizes or hand-picks tags from 215,240 real Suno dataset tags, weighted by rarity, and translates them into a style prompt. Edit the text below by hand afterward if you want.")
            }

            Section("Sound Direction (POS)") {
                TextField("Genre / fusion", text: $project.genre)
                TextEditor(text: $project.soundPrompt)
                    .frame(minHeight: 180)
            }

            Section("Negative Prompt (NEG)") {
                TextEditor(text: $project.negativePrompt)
                    .frame(minHeight: 140)
            }
        }
    }

    private func fusionSummary(_ dna: PromptDNA) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(dna.mode.displayName) · \(dna.selectedTags.count) tags")
                .font(.caption.bold())
            Text(dna.allTagNames.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var analysisView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if ai.isGenerating {
                    ProgressView("Analyzing…")
                }

                Text(analysis.isEmpty ? "Use the sparkle menu to analyze your lyrics." : analysis)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}
