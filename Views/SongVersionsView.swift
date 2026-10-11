import SwiftUI
import SwiftData

/// Version history for one song: save snapshots, inspect them, restore
/// one (the current state is saved first, so restoring never loses
/// work), or copy one out as a brand-new song.
struct SongVersionsView: View {
    @Bindable var project: SongProject
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isNaming = false
    @State private var newLabel = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newLabel = ""
                        isNaming = true
                    } label: {
                        Label("Save Current as Version", systemImage: "plus.circle.fill")
                    }
                }

                if project.versions.isEmpty {
                    Section {
                        Text("No versions yet. Anchord also saves one automatically before regenerating prompts or rebuilding lyrics.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("History") {
                        ForEach(project.sortedVersions) { version in
                            NavigationLink {
                                VersionDetailView(project: project, version: version) { dismiss() }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(version.displayName)
                                        .font(.headline)
                                    Text(version.createdAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let first = version.lyrics.split(whereSeparator: \.isNewline).first {
                                        Text(String(first))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let sorted = project.sortedVersions
                            for index in offsets {
                                modelContext.delete(sorted[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Version", isPresented: $isNaming) {
                TextField("Label (optional)", text: $newLabel)
                Button("Save") {
                    let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    project.saveVersion(label: label.isEmpty ? nil : label, in: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct VersionDetailView: View {
    let project: SongProject
    let version: SongVersion
    let onRestored: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingRestore = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Button {
                    isConfirmingRestore = true
                } label: {
                    Label("Restore This Version", systemImage: "arrow.uturn.backward.circle")
                }
                Button {
                    copyAsNewSong()
                } label: {
                    Label(copied ? "Copied to Your Songs" : "Copy as New Song", systemImage: copied ? "checkmark.circle" : "plus.square.on.square")
                }
                .disabled(copied)
            } footer: {
                Text("Restoring saves your current work as a version first.")
            }

            contentSection("Lyrics", version.lyrics)
            contentSection("Style (POS)", version.soundPrompt)
            contentSection("Exclude (NEG)", version.negativePrompt)
            contentSection("Suno Lyrics", version.sunoLyrics)
        }
        .navigationTitle(version.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Restore \(version.displayName)?", isPresented: $isConfirmingRestore, titleVisibility: .visible) {
            Button("Restore") {
                project.saveVersion(label: "Before restoring v\(version.number)", in: modelContext)
                project.restore(version)
                onRestored()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func contentSection(_ title: String, _ text: String) -> some View {
        if !text.isEmpty {
            Section(title) {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private func copyAsNewSong() {
        let song = SongProject(
            title: "\(version.title) (v\(version.number))",
            lyrics: version.lyrics,
            soundPrompt: version.soundPrompt,
            negativePrompt: version.negativePrompt,
            genre: version.genre
        )
        song.sunoLyrics = version.sunoLyrics
        song.promptDNAData = version.promptDNAData
        modelContext.insert(song)
        copied = true
    }
}
