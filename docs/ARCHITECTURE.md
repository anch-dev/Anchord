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

## Intelligence providers

### Apple Foundation Models

The first provider uses Apple's Foundation Models framework. It is the default when available and gives Anchord access to Apple's on-device language model.

The provider is isolated behind `AIProvider` so the UI and songwriting features do not depend directly on Foundation Models APIs.

### Local models

Downloaded open-source models are represented by `LocalModelDescriptor`.

The eventual model pipeline is:

1. Discover model metadata.
2. Determine device capabilities.
3. Recommend compatible quantization/model size.
4. Download from the Hugging Face Hub.
5. Verify the artifact.
6. Store it outside the app bundle.
7. Load it through an on-device inference adapter.
8. Route supported tasks to it.

The first implementation intentionally does not ship arbitrary model weights.

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

The current analyzer is intentionally lightweight. It provides an initial syllable estimate so the UI can ship early.

The production cadence engine should eventually combine:

- pronunciation dictionaries
- syllable counts
- stress patterns
- phoneme sequences
- vowel/consonant similarity
- line-length similarity

AI suggestions should use these measurements as constraints rather than replacing deterministic analysis.
