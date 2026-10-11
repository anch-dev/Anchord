import Foundation

/// The seam between Anchord and whatever on-device engine actually runs a
/// downloaded model. Nothing in the UI or songwriting layers depends on a
/// specific engine; `LocalModelProvider` only talks to this protocol.
///
/// No runtime ships in this build. Candidates under evaluation, in order:
/// - llama.cpp's Metal backend (it reads the GGUF files the catalog lists
///   directly; distributed as an XCFramework usable from Swift),
/// - MLX Swift (Apple Silicon native, but needs MLX-format weights rather
///   than GGUF, so the catalog would need MLX variants),
/// - Core ML (needs per-model conversion).
/// Whichever is adopted conforms here and is registered in
/// `LocalRuntimeRegistry.current`.
protocol LocalInferenceRuntime: Sendable {
    /// Human-readable engine name for Settings ("llama.cpp (Metal)").
    var name: String { get }
    /// File formats this engine can load, e.g. ["gguf"].
    var supportedFormats: Set<String> { get }

    func loadModel(at url: URL) async throws
    func unloadModel() async
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) async throws -> String
}

enum LocalRuntimeRegistry {
    /// Set by the integration that adds a real engine. `nil` means local
    /// models can be downloaded and verified but not run yet.
    nonisolated(unsafe) static var current: (any LocalInferenceRuntime)?
}
