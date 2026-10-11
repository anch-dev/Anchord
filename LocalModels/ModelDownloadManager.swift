import Foundation

/// Downloads catalog models from Hugging Face into `ModelStore`, verifies
/// size and SHA-256 against the catalog, and only then registers them as
/// installed. A model that fails verification is deleted, never
/// registered.
@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    enum State: Equatable {
        case idle
        case downloading(progress: Double, receivedBytes: Int64)
        case verifying
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]

    private let registry = InstalledModelRegistry.shared
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var models: [Int: LocalModelDescriptor] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = true
        config.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: config, delegate: DownloadDelegate(owner: self), delegateQueue: nil)
    }()

    func state(for id: String) -> State {
        states[id] ?? .idle
    }

    func isActive(_ id: String) -> Bool {
        switch state(for: id) {
        case .downloading, .verifying: true
        default: false
        }
    }

    func download(_ model: LocalModelDescriptor) {
        guard !isActive(model.id), !registry.isInstalled(model.id) else { return }
        guard let url = model.downloadURL else {
            states[model.id] = .failed("Invalid download address.")
            return
        }
        if let free = ModelStore.freeSpaceBytes, free < model.sizeBytes + 500_000_000 {
            let need = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
            states[model.id] = .failed("Not enough free storage. \(need) needed.")
            return
        }
        let task = session.downloadTask(with: url)
        tasks[model.id] = task
        models[task.taskIdentifier] = model
        states[model.id] = .downloading(progress: 0, receivedBytes: 0)
        task.resume()
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        states[id] = .idle
    }

    // MARK: Delegate callbacks (hopped to the main actor)

    fileprivate func progress(taskID: Int, received: Int64, expected: Int64) {
        guard let model = models[taskID], tasks[model.id] != nil else { return }
        let total = expected > 0 ? expected : model.sizeBytes
        states[model.id] = .downloading(progress: min(1, Double(received) / Double(max(total, 1))), receivedBytes: received)
    }

    fileprivate func finished(taskID: Int, stagedFile: URL?, httpStatus: Int?, error: String?) {
        guard let model = models.removeValue(forKey: taskID) else { return }
        tasks[model.id] = nil

        if let error {
            if let stagedFile { try? FileManager.default.removeItem(at: stagedFile) }
            // Cancellation already reset the state to idle.
            if states[model.id] != .idle { states[model.id] = .failed(error) }
            return
        }
        guard let stagedFile else {
            states[model.id] = .failed("The download produced no file.")
            return
        }
        if let httpStatus, !(200..<300).contains(httpStatus) {
            try? FileManager.default.removeItem(at: stagedFile)
            states[model.id] = .failed("Hugging Face returned HTTP \(httpStatus).")
            return
        }

        states[model.id] = .verifying
        Task {
            let result = await Self.verifyAndInstall(stagedFile: stagedFile, model: model)
            switch result {
            case .success(let installed):
                registry.register(installed)
                states[model.id] = .idle
            case .failure(let error):
                states[model.id] = .failed(error.message)
            }
        }
    }

    private struct VerificationError: Error {
        let message: String
    }

    /// Size check, streaming SHA-256, then move into permanent storage.
    /// Runs off the main actor: hashing a multi-GB file takes a while.
    private nonisolated static func verifyAndInstall(
        stagedFile: URL,
        model: LocalModelDescriptor
    ) async -> Result<InstalledModel, VerificationError> {
        await Task.detached(priority: .utility) { () -> Result<InstalledModel, VerificationError> in
            let fm = FileManager.default
            defer { try? fm.removeItem(at: stagedFile) }

            let size = (try? fm.attributesOfItem(atPath: stagedFile.path)[.size] as? Int64) ?? -1
            guard size == model.sizeBytes else {
                return .failure(VerificationError(message: "Downloaded size didn't match the catalog (\(size) vs \(model.sizeBytes) bytes)."))
            }
            guard let hash = try? ModelStore.sha256(of: stagedFile) else {
                return .failure(VerificationError(message: "Couldn't read the downloaded file to verify it."))
            }
            guard hash == model.sha256 else {
                return .failure(VerificationError(message: "Checksum mismatch. The file was discarded."))
            }
            do {
                _ = try ModelStore.prepareDirectory(modelID: model.id)
                let destination = ModelStore.fileURL(modelID: model.id, fileName: model.fileName)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: stagedFile, to: destination)
            } catch {
                return .failure(VerificationError(message: "Couldn't store the model: \(error.localizedDescription)"))
            }
            return .success(InstalledModel(
                id: model.id,
                displayName: model.titleWithQuantization,
                fileName: model.fileName,
                sizeBytes: model.sizeBytes,
                sha256: model.sha256,
                installedAt: .now
            ))
        }.value
    }
}

/// URLSession calls back on its own queue; this forwards to the
/// main-actor manager. The finished file must be moved out of the temp
/// location before `didFinishDownloadingTo` returns, so that happens here.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private weak var owner: ModelDownloadManager?
    private let lock = NSLock()
    private var staged: [Int: URL] = [:]

    init(owner: ModelDownloadManager) {
        self.owner = owner
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let id = downloadTask.taskIdentifier
        let owner = self.owner
        Task { @MainActor in
            owner?.progress(taskID: id, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("anchord-model-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staging)
            lock.lock()
            staged[downloadTask.taskIdentifier] = staging
            lock.unlock()
        } catch {
            // Reported as "no file" in didCompleteWithError.
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        lock.lock()
        let file = staged.removeValue(forKey: id)
        lock.unlock()
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let message = error?.localizedDescription
        let owner = self.owner
        Task { @MainActor in
            owner?.finished(taskID: id, stagedFile: file, httpStatus: status, error: message)
        }
    }
}
