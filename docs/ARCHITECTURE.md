# Anchord Architecture

## Product principle

Anchord is a songwriting IDE, not a generic chatbot.

The app owns the structured creative state:

- lyrics
- sections
- cadence measurements
- phonetic relationships
- prompt DNA
- generation history
- model preferences

AI providers operate on that structured state.

## Native app, iOS first

Anchord is a native Swift/SwiftUI app. There is no HTML, web view or
JavaScript UI layer, and none should be added. iPhone and iPad are the
primary targets; macOS will be a native SwiftUI target built on the same
shared code, with platform-specific UI behind `#if os(...)` /
`canImport` checks (see `Support/Clipboard.swift` and
`LocalModels/DeviceCapabilities.swift` for the pattern).

## Layers

| Layer | Where | Notes |
|---|---|---|
| UI | `Views/` | SwiftUI. Touch-first; no hover-only controls. |
| Application | `AI/AIService.swift`, `Models/SongProject.swift` | Song/version workflows, provider routing. |
| Creative engines | `Engine/`, `Analysis/`, `Data/` | Pure Swift, platform-independent. |
| AI providers | `AI/` | `AIProvider` protocol; Apple Foundation Models, local models. |
| Model system | `LocalModels/`, `Models/LocalModelDescriptor.swift`, `Resources/ModelCatalog.json` | Catalog, device fit, downloads, verification, registry. |
| Persistence | SwiftData (`SongProject`, `SongVersion`), Application Support files | Local-first. |

## Suno prompt engine (dataset-driven)

`TagDatabase` loads 215,240 tags mined from 659,788 Suno songs.
`FusionRandomizer` picks tags (rarity-weighted, category-balanced),
`PromptRoleEngine` assigns musical roles, and `SunoPromptGenerator`
writes POS/NEG in four modes. This is the prompt engine; it is not to be
replaced by a generic LLM prompt.

`PromptDNA` stores the tag selection plus `PromptIntent` (energy, vocals,
mood, instrumentation, production, mix, performance, avoid).
`PromptDNAComposer` layers the intent onto the generator's output as a
short "Direction:" sentence and extra NEG items, inside Suno's limits.
AI features (`AIService.reviewPrompt`) critique the output; they never
rewrite it wholesale.

Suno output is kept as three separate, editable fields on the song:
`soundPrompt` (POS), `negativePrompt` (NEG) and `sunoLyrics` (LYRICS,
built by `SunoLyricsFormatter` from the draft without touching it).

## Versions

`SongVersion` snapshots title, lyrics, POS, NEG, LYRICS, genre and
Prompt DNA. The editor saves one automatically before regenerating POS/
NEG, rebuilding LYRICS, saving a changed fusion, or restoring an older
version, so iterating never destroys work.

## Intelligence providers

### Apple Foundation Models

The first provider uses Apple's Foundation Models framework. It is the default when available and gives Anchord access to Apple's on-device language model.

The provider is isolated behind `AIProvider` so the UI and songwriting features do not depend directly on Foundation Models APIs.

Availability is checked live (`AppleFoundationModelProvider.status`) and
each request uses a fresh `LanguageModelSession`.

### Local models

Pipeline, with what exists today:

1. **Catalog**: done. `Resources/ModelCatalog.json` lists Q4_K_M GGUF builds
   of Qwen3 (1.7B, 4B Instruct 2507, 8B), Gemma 3 (1B, 4B), Llama 3.2 3B,
   Llama 3.1 8B, SmolLM3 3B and Phi-4 mini. The `Verify model catalog`
   workflow checks every repo, file, size and sha256 against the Hub.
2. **Device fit**: done. `DeviceCapabilities` reads physical memory,
   platform/idiom and the app's memory budget at runtime (no device-model
   table) and rates each model Recommended / May be slow / Not recommended.
3. **Download**: done. `ModelDownloadManager` downloads from the Hub's
   `resolve` endpoint with progress and cancel.
4. **Verify**: done. Size and streaming SHA-256 must match the catalog or
   the file is deleted.
5. **Store**: done. `Application Support/Models/<id>/`, excluded from backup.
6. **Registry**: done. `InstalledModelRegistry` persists verified models
   and the selected one.
7. **Inference runtime**: not yet. `LocalInferenceRuntime` is the
   seam; `LocalRuntimeRegistry.current` is `nil`, and the UI says so.
   llama.cpp's Metal backend is the leading candidate because it loads the
   catalog's GGUF files directly; MLX Swift would need MLX-format weights.
8. **Routing**: done. `LocalModelProvider` → `AIService`, chosen per song
   (Automatic prefers Apple Intelligence, then the selected local model).

## Model routing

Future routing should consider:

- task: lyric generation, cadence analysis, prompt engineering, etc.
- device family
- available memory
- model context length
- quantization
- measured tokens/second
- privacy preference
- whether Apple Intelligence is available

A user should never need to understand model formats to use the app.

## Persistence

SwiftData stores user projects locally. Cloud sync can be added later without making the core songwriting workflow dependent on a server.

## Cadence engine

`PhoneticEngine` estimates syllables (rules plus an exception list),
stress, and rhyme tails from spelling, and classifies rhymes as perfect,
slant (assonance) or consonance. `CadenceAnalyzer` builds per-stanza
rhyme schemes, internal rhymes and off-pocket lines (±3 syllables from
the stanza average). These are estimates, and the UI labels them that
way. Rewrites put cadence/pocket first, then phonetic flow, then meaning.

A production engine should still add:

- pronunciation dictionaries
- syllable counts
- stress patterns
- phoneme sequences
- vowel/consonant similarity
- line-length similarity

AI suggestions should use these measurements as constraints rather than replacing deterministic analysis.
