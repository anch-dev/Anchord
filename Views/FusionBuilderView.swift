import SwiftUI

/// The native Song Editor's prompt-generation surface -- same engine as
/// the dataset-mining prototype (215,240 real tags from 659,788 songs,
/// rarity-weighted selection, category balancing, four distinct
/// generation modes), presented as a proper SwiftUI sheet instead of a
/// web view. Writes its result into the host `SongProject`'s
/// `soundPrompt` / `negativePrompt` / `promptDNA`.
struct FusionBuilderView: View {
    @Bindable var project: SongProject
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var database = TagDatabase.shared

    @State private var mode: FusionMode = .blended
    @State private var tagCount: Int = 5
    @State private var rarityMode: RarityMode = .rare
    @State private var raritySlider: Double = 70
    @State private var categoryBalanceOn = false
    @State private var minCategories = 3
    @State private var enabledCategories: Set<TagCategory> = Set(TagCategory.allCases.filter(\.enabledByDefault))
    @State private var chaosOn = false
    @State private var songLengthSeconds = 240
    @State private var selected: [MusicTag] = []
    @State private var anchorNames: Set<String> = []
    @State private var generatedPrompt = ""
    @State private var generatedNegative = ""
    @State private var showSearch = false

    private static let lengthOptions = [60, 90, 120, 150, 180, 240, 300, 360, 420, 480]
    private static let countOptions = [3, 4, 5, 6, 7, 8, 10]

    var body: some View {
        NavigationStack {
            Form {
                if !database.isLoaded {
                    Section {
                        if let error = database.loadError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        } else {
                            ProgressView("Loading tag database…")
                        }
                    }
                } else {
                    modeSection
                    countSection
                    raritySection
                    if mode == .sectioned { lengthSection }
                    categoryBalanceSection
                    categorySection
                    selectedSection
                    if !generatedPrompt.isEmpty { previewSection }
                }
            }
            .navigationTitle("Fusion Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search Tags") { showSearch = true }
                }
            }
            .sheet(isPresented: $showSearch) {
                TagSearchView(selected: $selected)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .task {
                await database.loadIfNeeded()
                loadExistingSelection()
            }
        }
    }

    // MARK: - Sections

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(FusionMode.allCases) { m in Text(m.displayName).tag(m) }
            }
            .pickerStyle(.segmented)
            Text(mode.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var countSection: some View {
        Section("Tag Count") {
            Picker("Tags", selection: $tagCount) {
                ForEach(Self.countOptions, id: \.self) { n in Text("\(n)").tag(n) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var raritySection: some View {
        Section("Rarity Weighting") {
            Picker("Rarity mode", selection: $rarityMode) {
                ForEach(RarityMode.allCases) { m in Text(m.displayName).tag(m) }
            }
            .onChange(of: rarityMode) { _, newValue in raritySlider = newValue.defaultSlider }

            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $raritySlider, in: 0...100)
                Text(FusionRandomizer.rarityBand(forSlider: raritySlider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Chaos Mode", isOn: $chaosOn)
            if chaosOn {
                Text("Relaxes category balancing and rotates each tag's musical role, producing deliberately unusual combinations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lengthSection: some View {
        Section("Song Length") {
            Picker("Length", selection: $songLengthSeconds) {
                ForEach(Self.lengthOptions, id: \.self) { sec in
                    Text(timeString(sec)).tag(sec)
                }
            }
            Text("Each section gets an explicit [mm:ss–mm:ss] timestamp so Suno holds the boundary instead of blending through it. 8:00 is Suno's current generation ceiling.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryBalanceSection: some View {
        Section {
            Toggle("Category-Balanced", isOn: $categoryBalanceOn)
            if categoryBalanceOn {
                Stepper("At least \(minCategories) different categories", value: $minCategories, in: 2...5)
            }
        }
    }

    private var categorySection: some View {
        Section("Categories Included") {
            FlowLayout(spacing: 8) {
                ForEach(TagCategory.allCases) { category in
                    categoryChip(category)
                }
            }
        }
    }

    private func categoryChip(_ category: TagCategory) -> some View {
        let isOn = enabledCategories.contains(category)
        let count = database.tagsByCategory[category]?.count ?? 0
        return Button {
            if isOn { enabledCategories.remove(category) } else { enabledCategories.insert(category) }
        } label: {
            Label("\(category.displayName) · \(count)", systemImage: category.symbolName)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var selectedSection: some View {
        Section("Your Fusion") {
            if selected.isEmpty {
                Text("Tap Random Fusion, or search for specific tags.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selected) { tag in
                    HStack {
                        Image(systemName: tag.category.symbolName)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(tag.name)
                            Text("\(tag.category.displayName) · \(tag.songCountDescription)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if mode == .hybrid {
                            Button {
                                toggleAnchor(tag)
                            } label: {
                                Image(systemName: anchorNames.contains(tag.name.lowercased()) ? "star.fill" : "star")
                                    .foregroundStyle(anchorNames.contains(tag.name.lowercased()) ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            selected.removeAll { $0.id == tag.id }
                            anchorNames.remove(tag.name.lowercased())
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Generated Prompt") {
            Text(generatedPrompt)
                .font(.callout)
            Text("\(generatedPrompt.count) / 1000 characters")
                .font(.caption2)
                .foregroundStyle(generatedPrompt.count > 1000 ? .red : .secondary)
            if !generatedNegative.isEmpty {
                Divider()
                Text("Negative Prompt")
                    .font(.caption.bold())
                Text(generatedNegative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                randomFusion()
            } label: {
                Label("Random Fusion", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!database.isLoaded)

            HStack(spacing: 10) {
                Button("Generate Prompt") { generate() }
                    .buttonStyle(.bordered)
                    .disabled(selected.isEmpty)
                Button("Save to Song") { saveToProject() }
                    .buttonStyle(.borderedProminent)
                    .disabled(generatedPrompt.isEmpty)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Actions

    private func randomFusion() {
        let pool = database.pool(for: enabledCategories)
        let power = FusionRandomizer.weightPower(forSlider: raritySlider)

        var result: [MusicTag]
        if categoryBalanceOn {
            result = FusionRandomizer.categoryBalancedFusion(
                tagsByCategory: database.tagsByCategory,
                enabledCategories: enabledCategories,
                tagCount: tagCount,
                minCategories: minCategories,
                power: power,
                weirdBoost: rarityMode == .weird
            )
        } else {
            result = FusionRandomizer.simpleFusion(pool: pool, count: tagCount, power: power, weirdBoost: rarityMode == .weird)
        }

        if mode == .evolution || mode == .sectioned {
            result = SunoPromptGenerator.orderedForSequence(result)
        }
        selected = result
        anchorNames = mode == .hybrid
            ? SunoPromptGenerator.chooseAnchorNames(from: result, count: max(1, min(3, Int((Double(result.count) / 4).rounded()))))
            : []
        generatedPrompt = ""
        generatedNegative = ""
    }

    private func toggleAnchor(_ tag: MusicTag) {
        let key = tag.name.lowercased()
        if anchorNames.contains(key) { anchorNames.remove(key) } else { anchorNames.insert(key) }
    }

    private func generate() {
        let options = PromptGenerationOptions(chaos: chaosOn, songLengthSeconds: songLengthSeconds)
        generatedPrompt = SunoPromptGenerator.generatePrompt(tags: selected, mode: mode, anchorNames: anchorNames, options: options)
        generatedNegative = SunoPromptGenerator.generateNegativePrompt(tags: selected, mode: mode)
    }

    private func saveToProject() {
        project.soundPrompt = generatedPrompt
        project.negativePrompt = generatedNegative
        project.genre = selected.first(where: { $0.category == .genre || $0.category == .subgenre })?.name ?? project.genre
        project.promptDNA = PromptDNA(
            selectedTags: selected,
            mode: mode,
            anchorNames: anchorNames,
            chaosEnabled: chaosOn,
            songLengthSeconds: songLengthSeconds
        )
        project.updatedAt = .now
        dismiss()
    }

    private func loadExistingSelection() {
        let dna = project.promptDNA
        guard !dna.selectedTags.isEmpty else { return }
        selected = dna.selectedTags
        mode = dna.mode
        anchorNames = dna.anchorNames
        chaosOn = dna.chaosEnabled
        songLengthSeconds = dna.songLengthSeconds
        generatedPrompt = project.soundPrompt
        generatedNegative = project.negativePrompt
    }

    private func timeString(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

/// Manual tag search, for building a fusion by hand instead of (or in
/// addition to) randomizing.
struct TagSearchView: View {
    @Binding var selected: [MusicTag]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var database = TagDatabase.shared
    @State private var query = ""

    private var results: [MusicTag] { database.search(query) }

    var body: some View {
        NavigationStack {
            List(results) { tag in
                Button {
                    if !selected.contains(where: { $0.id == tag.id }) {
                        selected.append(tag)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tag.name).foregroundStyle(.primary)
                            Text(tag.category.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tag.songCountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if selected.contains(where: { $0.id == tag.id }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search 215,240 tags")
            .navigationTitle("Tag Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Minimal wrapping flow layout for the category-chip grid. SwiftUI has
/// no built-in wrap layout prior to custom `Layout` conformances, so this
/// is a small native implementation rather than reaching for a web-style
/// flexbox workaround.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
