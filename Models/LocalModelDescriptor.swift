import Foundation

/// One downloadable local model. Every field comes from
/// `Resources/ModelCatalog.json`, which CI checks against the live
/// Hugging Face Hub (`scripts/verify_model_catalog.py`): the repository
/// exists and is ungated, the file exists, and `sizeBytes`/`sha256` match.
struct LocalModelDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let family: String
    let displayName: String
    let repository: String
    let fileName: String
    let quantization: String
    let sizeBytes: Int64
    let sha256: String
    /// Physical memory (GB) at which this model is recommended. Below it
    /// the model may still load but is likely to be slow or get killed.
    let minimumMemoryGB: Int
    let license: String
    let strengths: [String]
    let summary: String

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    /// "Qwen3 4B Instruct 2507 — Q4_K_M"
    var titleWithQuantization: String { "\(displayName) — \(quantization)" }

    var huggingFaceURL: URL? {
        URL(string: "https://huggingface.co/\(repository)")
    }

    /// Direct file download from the Hub's `resolve` endpoint.
    var downloadURL: URL? {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(fileName)")
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }
}

/// The bundled, Hub-verified catalog.
enum ModelCatalog {
    private struct File: Decodable {
        let version: Int
        let models: [LocalModelDescriptor]
    }

    static let models: [LocalModelDescriptor] = {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return []
        }
        return file.models
    }()

    static func model(id: String) -> LocalModelDescriptor? {
        models.first { $0.id == id }
    }
}
