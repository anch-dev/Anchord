import Foundation
import CryptoKit

/// A model that has been downloaded *and* verified. Only the registry
/// creates these, and only after the checksum matched the catalog.
struct InstalledModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let sizeBytes: Int64
    let sha256: String
    let installedAt: Date

    var fileURL: URL { ModelStore.fileURL(modelID: id, fileName: fileName) }
}

/// App-managed model storage: Application Support/Models/<id>/<file>,
/// excluded from iCloud/iTunes backup (multi-GB, re-downloadable).
enum ModelStore {
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    static func directory(modelID: String) -> URL {
        rootDirectory.appendingPathComponent(modelID, isDirectory: true)
    }

    static func fileURL(modelID: String, fileName: String) -> URL {
        directory(modelID: modelID).appendingPathComponent(fileName)
    }

    static var registryURL: URL {
        rootDirectory.appendingPathComponent("installed.json")
    }

    static func prepareDirectory(modelID: String) throws -> URL {
        var root = rootDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)

        let dir = directory(modelID: modelID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func remove(modelID: String) {
        try? FileManager.default.removeItem(at: directory(modelID: modelID))
    }

    static var freeSpaceBytes: Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Streaming SHA-256 so multi-GB files never sit in memory at once.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 8 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Persistent list of verified, installed models, plus which one the
/// local provider should use.
@MainActor
final class InstalledModelRegistry: ObservableObject {
    static let shared = InstalledModelRegistry()

    @Published private(set) var models: [InstalledModel] = []
    @Published var selectedModelID: String? {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: Self.selectedKey) }
    }

    private static let selectedKey = "anchord.localModel.selectedID"

    private init() {
        selectedModelID = UserDefaults.standard.string(forKey: Self.selectedKey)
        load()
    }

    var selectedModel: InstalledModel? {
        guard let selectedModelID else { return nil }
        return models.first { $0.id == selectedModelID }
    }

    func isInstalled(_ id: String) -> Bool {
        models.contains { $0.id == id }
    }

    func register(_ model: InstalledModel) {
        models.removeAll { $0.id == model.id }
        models.append(model)
        if selectedModelID == nil { selectedModelID = model.id }
        save()
    }

    func remove(_ id: String) {
        ModelStore.remove(modelID: id)
        models.removeAll { $0.id == id }
        if selectedModelID == id { selectedModelID = models.first?.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: ModelStore.registryURL),
              let decoded = try? JSONDecoder().decode([InstalledModel].self, from: data) else { return }
        // Drop entries whose files were removed (e.g. storage cleanup).
        models = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        try? FileManager.default.createDirectory(at: ModelStore.rootDirectory, withIntermediateDirectories: true)
        try? data.write(to: ModelStore.registryURL, options: .atomic)
    }
}
