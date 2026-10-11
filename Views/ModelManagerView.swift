import SwiftUI

/// AI Settings: Apple Intelligence status, this device's capabilities,
/// and the Hub-verified local model catalog ranked for this device.
struct ModelManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var registry = InstalledModelRegistry.shared
    @ObservedObject private var downloads = ModelDownloadManager.shared

    @State private var device: DeviceCapabilities?
    @State private var isShowingLyricPreferences = false

    var body: some View {
        NavigationStack {
            List {
                appleSection
                Section {
                    Button {
                        isShowingLyricPreferences = true
                    } label: {
                        Label("Lyric Preferences", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Banned words, preferred vocabulary and style rules every AI provider follows.")
                }
                if let device {
                    deviceSection(device)
                    installedSection
                    catalogSections(device)
                }
                runtimeSection
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                device = DeviceCapabilities.current()
            }
            .sheet(isPresented: $isShowingLyricPreferences) {
                LyricPreferencesView()
            }
        }
    }

    // MARK: Sections

    private var appleSection: some View {
        let status = AppleFoundationModelProvider.status
        return Section {
            HStack(spacing: 12) {
                Image(systemName: "apple.intelligence")
                    .font(.title2)
                    .foregroundStyle(status.isReady ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                        .font(.headline)
                    Text(status.isReady ? "Available on this device" : status.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(status.isReady ? Color.green : Color.orange)
            }
        } footer: {
            Text("Preferred whenever it's available. Songs set to Automatic fall back to your selected local model.")
        }
    }

    private func deviceSection(_ device: DeviceCapabilities) -> some View {
        Section("This \(device.platformName)") {
            LabeledContent("Memory", value: "\(device.memoryGB) GB")
            if let budget = device.appMemoryBudgetBytes {
                LabeledContent("Available to Anchord", value: ByteCountFormatter.string(fromByteCount: Int64(budget), countStyle: .memory))
            }
            LabeledContent("Apple silicon", value: device.isAppleSilicon ? "Yes" : "No")
            if let free = ModelStore.freeSpaceBytes {
                LabeledContent("Free storage", value: ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
            }
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        if !registry.models.isEmpty {
            Section {
                Picker("Use for local AI", selection: $registry.selectedModelID) {
                    ForEach(registry.models) { model in
                        Text(model.displayName).tag(Optional(model.id))
                    }
                }
            } header: {
                Text("Installed")
            } footer: {
                Text("Downloaded and checksum-verified against Hugging Face.")
            }
        }
    }

    @ViewBuilder
    private func catalogSections(_ device: DeviceCapabilities) -> some View {
        let ranked = ModelCatalog.models.map { RankedModel(model: $0, fit: device.fit(for: $0)) }
        let recommended = ranked.filter { $0.fit == .recommended }.sorted { $0.model.sizeBytes > $1.model.sizeBytes }
        let others = ranked.filter { $0.fit != .recommended }.sorted { $0.model.sizeBytes < $1.model.sizeBytes }
        let best = device.bestModel(in: ModelCatalog.models)?.id

        if ModelCatalog.models.isEmpty {
            Section {
                Text("The model catalog couldn't be loaded.")
                    .foregroundStyle(.secondary)
            }
        }
        if !recommended.isEmpty {
            Section {
                ForEach(recommended) { item in
                    ModelRow(model: item.model, fit: item.fit, isBestFit: item.id == best)
                }
            } header: {
                Text("Recommended for this \(device.platformName)")
            } footer: {
                Text("Based on \(device.memoryGB) GB of memory. Recommendations, not guarantees.")
            }
        }
        if !others.isEmpty {
            Section("Other Models") {
                ForEach(others) { item in
                    ModelRow(model: item.model, fit: item.fit, isBestFit: false)
                }
            }
        }
    }

    private var runtimeSection: some View {
        Section {
            if let runtime = LocalRuntimeRegistry.current {
                LabeledContent("Local engine", value: runtime.name)
            } else {
                Label {
                    Text("This build doesn't include a local inference engine yet. You can download and verify models now; they'll run once the engine ships.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Local Inference")
        }
    }
}

private struct RankedModel: Identifiable {
    let model: LocalModelDescriptor
    let fit: DeviceCapabilities.Fit
    var id: String { model.id }
}

private struct ModelRow: View {
    let model: LocalModelDescriptor
    let fit: DeviceCapabilities.Fit
    let isBestFit: Bool

    @ObservedObject private var registry = InstalledModelRegistry.shared
    @ObservedObject private var downloads = ModelDownloadManager.shared
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.titleWithQuantization)
                    .font(.headline)
                Spacer(minLength: 8)
                if isBestFit {
                    Text("Best fit")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text("\(model.sizeDescription) · \(model.license) · \(fit.label)")
                .font(.caption)
                .foregroundStyle(fit == .notRecommended ? Color.orange : Color.secondary)

            Text(model.summary)
                .font(.subheadline)

            Text(model.strengths.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)

            statusView

            HStack(spacing: 12) {
                actionButton
                Spacer()
                if let url = model.huggingFaceURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Hugging Face", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens \(model.repository) on huggingface.co")
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { registry.remove(model.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees \(model.sizeDescription). You can download it again later.")
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch downloads.state(for: model.id) {
        case .downloading(let progress, let received):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text("\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) of \(model.sizeDescription)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            HStack(spacing: 8) {
                ProgressView()
                Text("Verifying checksum…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if registry.isInstalled(model.id) {
            HStack(spacing: 8) {
                if registry.selectedModelID == model.id {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Use") { registry.selectedModelID = model.id }
                        .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete model")
            }
        } else if downloads.isActive(model.id) {
            Button("Cancel") { downloads.cancel(model.id) }
                .buttonStyle(.bordered)
        } else {
            Button {
                downloads.download(model)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
