import SwiftUI
import SwiftData

/// Home screen: a welcoming dashboard instead of a bare list. Hero
/// "New Song" card, a "continue writing" card for the latest project,
/// quick actions into the Fusion Builder and model manager, and the
/// song library as a grid of tinted cards.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SongProject.updatedAt, order: .reverse) private var projects: [SongProject]

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var isShowingModels = false
    @State private var fusionProject: SongProject?
    @State private var pendingFusionID: UUID?

    private var filteredProjects: [SongProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.genre.localizedCaseInsensitiveContains(query)
                || $0.lyrics.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HomeHeader(onShowModels: { isShowingModels = true })

                    if projects.isEmpty {
                        EmptyLibraryCard(action: createSong)
                    } else {
                        StatsStrip(projects: projects)
                        NewSongHeroCard(action: createSong)
                        if let latest = projects.first {
                            ContinueCard(project: latest) { path.append(latest.id) }
                        }
                        quickActions
                        librarySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AnchordBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let project = projects.first(where: { $0.id == id }) {
                    SongEditorView(project: project)
                }
            }
        }
        .sheet(isPresented: $isShowingModels) {
            ModelManagerView()
        }
        .sheet(item: $fusionProject, onDismiss: {
            // Land in the editor for the song the fusion was built for.
            if let id = pendingFusionID { path.append(id) }
            pendingFusionID = nil
        }) { project in
            FusionBuilderView(project: project)
        }
    }

    // MARK: Sections

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Tools")
            HStack(spacing: 12) {
                QuickActionTile(
                    title: "Fusion Builder",
                    subtitle: "215K real tags",
                    systemImage: "wand.and.stars",
                    palette: .sunset
                ) {
                    let project = SongProject(title: "Untitled Fusion")
                    modelContext.insert(project)
                    pendingFusionID = project.id
                    fusionProject = project
                }
                QuickActionTile(
                    title: "AI Models",
                    subtitle: "On-device",
                    systemImage: "cpu",
                    palette: .ocean
                ) {
                    isShowingModels = true
                }
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Your Songs")
                Spacer()
                Text("\(projects.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if projects.count > 3 {
                SearchField(text: $searchText)
            }

            if filteredProjects.isEmpty {
                Text("No songs match “\(searchText)”.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(filteredProjects) { project in
                        Button {
                            path.append(project.id)
                        } label: {
                            SongCard(project: project)
                        }
                        .buttonStyle(PressableCardStyle())
                        .contextMenu {
                            Button {
                                duplicate(project)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func createSong() {
        let project = SongProject()
        modelContext.insert(project)
        path.append(project.id)
    }

    private func duplicate(_ project: SongProject) {
        let copy = SongProject(
            title: "\(project.title) Copy",
            lyrics: project.lyrics,
            soundPrompt: project.soundPrompt,
            negativePrompt: project.negativePrompt,
            genre: project.genre
        )
        copy.promptDNAData = project.promptDNAData
        copy.sunoLyrics = project.sunoLyrics
        modelContext.insert(copy)
    }
}

extension SongProject {
    /// Non-blank lyric lines.
    var lyricLines: [String] {
        lyrics
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Header & background

private struct HomeHeader: View {
    let onShowModels: () -> Void

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Late-night session"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(CardPalette.violet.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Anchord")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Button(action: onShowModels) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI Models")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(greeting.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text("What are we writing today?")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .bold))
    }
}

// MARK: - Stats

private struct StatsStrip: View {
    let projects: [SongProject]

    var body: some View {
        let lines = projects.reduce(0) { $0 + $1.lyricLines.count }
        let prompts = projects.filter { !$0.soundPrompt.isEmpty }.count

        HStack(spacing: 0) {
            stat(value: projects.count, label: projects.count == 1 ? "Song" : "Songs")
            Divider().frame(height: 28)
            stat(value: lines, label: lines == 1 ? "Line" : "Lines")
            Divider().frame(height: 28)
            stat(value: prompts, label: prompts == 1 ? "Prompt" : "Prompts")
        }
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hero

private struct NewSongHeroCard: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                AnimatedMesh(isAnimating: !reduceMotion)

                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.white.opacity(0.12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 18, y: -12)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Start a New Song")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("Lyrics, cadence and a Suno-ready prompt, all in one place.")
                            .font(.subheadline)
                            .opacity(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.purple)
                        .frame(width: 52, height: 52)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .purple.opacity(0.35), radius: 18, y: 10)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Start a new song")
    }
}

private struct AnimatedMesh: View {
    let isAnimating: Bool

    var body: some View {
        if isAnimating {
            TimelineView(.animation) { context in
                mesh(time: Float(context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            mesh(time: 0)
        }
    }

    private func mesh(time: Float) -> some View {
        let dx = 0.18 * sin(time * 0.5)
        let dy = 0.14 * cos(time * 0.4)
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(0.5 + dx, 0.5 + dy), SIMD2(1, 0.5),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
        let colors: [Color] = [
            .indigo, .purple, .pink,
            .blue, .purple, .orange,
            .indigo, .pink, .orange,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }
}

// MARK: - Continue card

private struct ContinueCard: View {
    let project: SongProject
    let action: () -> Void

    var body: some View {
        let palette = CardPalette.forID(project.id)
        let excerpt = project.lyricLines.prefix(2)

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Pick Up Where You Left Off")

            Button(action: action) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.gradient)
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(.headline)
                            .lineLimit(1)
                        if excerpt.isEmpty {
                            Text("No lyrics yet. Tap to start writing.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(excerpt.joined(separator: " / "))
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text("Edited \(project.updatedAt, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
            .buttonStyle(PressableCardStyle())
        }
    }
}

// MARK: - Quick actions

private struct QuickActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let palette: CardPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(palette.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - Library

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search titles, genres, lyrics", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SongCard: View {
    let project: SongProject

    var body: some View {
        let palette = CardPalette.forID(project.id)
        let firstLine = project.lyricLines.first

        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                palette.gradient
                Image(systemName: "waveform")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white.opacity(0.18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                if !project.genre.isEmpty {
                    Text(project.genre)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                        .padding(10)
                }
            }
            .frame(height: 78)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(firstLine ?? "No lyrics yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                Text(project.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .multilineTextAlignment(.leading)
    }
}

// MARK: - Empty state

private struct EmptyLibraryCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(CardPalette.bloom.gradient)
                    .frame(width: 128, height: 128)
                    .blur(radius: 28)
                    .opacity(0.6)
                Image(systemName: "music.note.list")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(CardPalette.violet.gradient)
            }
            .frame(height: 140)

            VStack(spacing: 8) {
                Text("Your first song starts here")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Write lyrics, keep your cadence in check, and turn the vibe into a ready-to-use music prompt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                Label("Start a New Song", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CardPalette.violet.gradient, in: Capsule())
                    .shadow(color: .purple.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(PressableCardStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.top, 12)
    }
}
