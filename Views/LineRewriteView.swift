import SwiftUI

/// Rewrite one line with AI, cadence first. Every suggestion is re-measured
/// by Anchord's own analyzer so the writer can see whether it actually
/// kept the pocket and the rhyme, rather than trusting the model.
struct LineRewriteView: View {
    let line: LineAnalysis
    let song: LyricAnalysis
    let preference: AIProviderPreference
    @ObservedObject var ai: AIService
    let onReplace: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var suggestions: [String] = []
    @State private var errorMessage: String?
    @State private var hiddenForBans = 0
    @State private var isShowingPreferences = false

    private static let quickInstructions = [
        "Tighter", "More vivid", "Stronger rhyme", "Simpler words", "More internal rhyme", "Less cliché",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Original") {
                    Text(line.text)
                        .font(.body.weight(.medium))
                    LabeledContent("Syllables", value: "\(line.syllableCount)")
                    LabeledContent("Stress") {
                        Text(line.stressPattern)
                            .font(.callout.monospaced())
                    }
                    if !line.endRhymeTail.isEmpty {
                        LabeledContent("Rhymes on", value: "-\(line.endRhymeTail.replacingOccurrences(of: "_", with: "e"))")
                    }
                }

                Section {
                    TextField("What should change? (optional)", text: $instruction, axis: .vertical)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.quickInstructions, id: \.self) { quick in
                                Button(quick) { instruction = quick }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                    Button {
                        generate()
                    } label: {
                        if ai.isGenerating {
                            ProgressView()
                        } else {
                            Label("Suggest Rewrites", systemImage: "sparkles")
                        }
                    }
                    .disabled(ai.isGenerating)
                } header: {
                    Text("Instruction")
                } footer: {
                    Text("Follows your Lyric Preferences (\(LyricPreferencesStore.shared.preferences.priority.displayName.lowercased()), banned words, style). Your instruction can change priorities, never bans.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if hiddenForBans > 0 {
                    Section {
                        Label("\(hiddenForBans) suggestion\(hiddenForBans == 1 ? "" : "s") hidden for using a banned word.", systemImage: "nosign")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            SuggestionRow(original: line, suggestion: suggestion) {
                                onReplace(suggestion)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rewrite Line \(line.id + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingPreferences = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Lyric Preferences")
                }
            }
            .sheet(isPresented: $isShowingPreferences) {
                LyricPreferencesView()
            }
        }
    }

    private func generate() {
        errorMessage = nil
        hiddenForBans = 0
        Task {
            do {
                let result = try await ai.rewriteLine(line, in: song, instruction: instruction, preference: preference)
                suggestions = result.suggestions
                hiddenForBans = result.hiddenForBans
                if suggestions.isEmpty, hiddenForBans == 0 { errorMessage = "The model didn't return any usable lines. Try again." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SuggestionRow: View {
    let original: LineAnalysis
    let suggestion: String
    let onUse: () -> Void

    var body: some View {
        let measured = CadenceAnalyzer().analyze(suggestion).first
        let syllables = measured?.syllableCount ?? 0
        let delta = syllables - original.syllableCount
        let originalLast = original.words.last ?? ""
        let newLast = measured?.words.last ?? ""
        let rhyme = PhoneticEngine.rhyme(originalLast, newLast)
        let sameEnding = PhoneticEngine.letters(originalLast) == PhoneticEngine.letters(newLast) && !newLast.isEmpty
        let cliches = LyricPreferencesStore.shared.preferences.clichesFound(in: suggestion)

        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion)
                .font(.body)
                .textSelection(.enabled)
            if !cliches.isEmpty {
                Label("Cliché: \(cliches.joined(separator: ", "))", systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Label(delta == 0 ? "\(syllables) syl" : "\(syllables) syl (\(delta > 0 ? "+" : "")\(delta))",
                      systemImage: abs(delta) <= 1 ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(abs(delta) <= 1 ? .green : .orange)
                if sameEnding {
                    Label("Same end word", systemImage: "equal.circle")
                        .foregroundStyle(.secondary)
                } else if let rhyme {
                    Label("\(rhyme.rawValue) rhyme", systemImage: "music.note")
                        .foregroundStyle(rhyme == .perfect ? .green : .secondary)
                } else {
                    Label("No rhyme", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use", action: onUse)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
