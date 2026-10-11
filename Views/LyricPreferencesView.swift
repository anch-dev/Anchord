import SwiftUI

/// Lyric engine customization: banned words, preferred vocabulary and
/// style rules that analysis flags and every AI request obeys.
struct LyricPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LyricPreferencesStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WordListEditor(
                        words: $store.preferences.bannedWords,
                        placeholder: "Add a word or phrase",
                        tint: .red
                    )
                } header: {
                    Text("Banned Words")
                } footer: {
                    Text("Flagged in Analysis and never used by AI rewrites. Suggestions that slip one in are hidden. Single words match whole words only, so banning “fire” won't flag “firefly”.")
                }

                Section {
                    WordListEditor(
                        words: $store.preferences.preferredWords,
                        placeholder: "Add vocabulary to lean toward",
                        tint: .accentColor
                    )
                } header: {
                    Text("Preferred Words")
                } footer: {
                    Text("AI rewrites favor these where they fit naturally.")
                }

                Section {
                    Toggle("Flag clichés", isOn: $store.preferences.flagCliches)
                    Picker("Rewrite priority", selection: $store.preferences.priority) {
                        ForEach(LyricPreferences.RewritePriority.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Rhyme", selection: $store.preferences.rhymeStyle) {
                        ForEach(LyricPreferences.RhymeStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Explicit content", selection: $store.preferences.explicitContent) {
                        ForEach(LyricPreferences.ExplicitContent.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Point of view", selection: $store.preferences.perspective) {
                        ForEach(LyricPreferences.Perspective.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Tense", selection: $store.preferences.tense) {
                        ForEach(LyricPreferences.Tense.allCases) { Text($0.displayName).tag($0) }
                    }
                } header: {
                    Text("Style")
                } footer: {
                    Text("Cadence first is the default: syllables and stress, then sound, then meaning.")
                }

                Section {
                    Toggle("Syllable target per line", isOn: $store.preferences.targetSyllablesEnabled)
                    if store.preferences.targetSyllablesEnabled {
                        Stepper("Minimum: \(store.preferences.targetSyllablesMin)",
                                value: $store.preferences.targetSyllablesMin, in: 1...store.preferences.targetSyllablesMax)
                        Stepper("Maximum: \(store.preferences.targetSyllablesMax)",
                                value: $store.preferences.targetSyllablesMax, in: store.preferences.targetSyllablesMin...30)
                    }
                } header: {
                    Text("Pocket")
                } footer: {
                    Text("Lines outside the range are flagged in Analysis, in addition to lines far from their section's average.")
                }

                Section {
                    TextField("e.g. Southern slang, ocean imagery, no “gonna”", text: $store.preferences.styleNotes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Style Notes")
                } footer: {
                    Text("Sent to the AI with every request.")
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        store.preferences = LyricPreferences()
                    }
                }
            }
            .navigationTitle("Lyric Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Chip list with an add field. Tap a chip to remove it.
private struct WordListEditor: View {
    @Binding var words: [String]
    let placeholder: String
    let tint: Color

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(placeholder, text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add")
            }

            if !words.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(words, id: \.self) { word in
                        Button {
                            words.removeAll { $0 == word }
                        } label: {
                            HStack(spacing: 4) {
                                Text(word)
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.14), in: Capsule())
                            .foregroundStyle(tint)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(word)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func add() {
        // Commas let the writer paste several at once: "fire, desire, tonight".
        let entries = draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        for entry in entries where !words.contains(entry) {
            words.append(entry)
        }
        draft = ""
    }
}
