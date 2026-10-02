import Foundation

struct LocalModelDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let repository: String
    let fileName: String
    let sizeBytes: Int64
    let minimumMemoryGB: Int
    let recommendedDeviceFamilies: [String]
    let specialties: [String]
    let quantization: String

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Initial catalog shape only. Do not treat these entries as downloadable models yet.
/// A future signed catalog can supply real Hugging Face metadata and compatibility data.
enum ModelCatalog {
    static let examples: [LocalModelDescriptor] = [
        LocalModelDescriptor(
            id: "example-small-lyric",
            name: "Small Lyric Model",
            repository: "TODO/HuggingFaceRepo",
            fileName: "model.Q4_K_M.gguf",
            sizeBytes: 1_500_000_000,
            minimumMemoryGB: 4,
            recommendedDeviceFamilies: ["iPhone", "iPad", "Mac"],
            specialties: ["quick rewrites", "brainstorming"],
            quantization: "Q4_K_M"
        ),
        LocalModelDescriptor(
            id: "example-medium-lyric",
            name: "Medium Lyric Model",
            repository: "TODO/HuggingFaceRepo",
            fileName: "model.Q4_K_M.gguf",
            sizeBytes: 4_500_000_000,
            minimumMemoryGB: 8,
            recommendedDeviceFamilies: ["iPhone Pro", "iPad Pro", "Mac"],
            specialties: ["long-form lyrics", "structured rewriting"],
            quantization: "Q4_K_M"
        )
    ]
}
