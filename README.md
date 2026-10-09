# Anchord

**Anchord** is a native Apple-platform songwriting workbench built around Apple Intelligence and optional on-device open-source models.

The goal is simple: help writers preserve **cadence, pocket, phonetic shape, and intent** while turning ideas into structured prompts for music-generation tools.

## Architecture

- SwiftUI for the UI
- SwiftData for local projects and history
- Foundation Models for Apple Intelligence on supported devices
- A provider abstraction for future local Hugging Face/Core ML/MLX models
- No required server for the core songwriting workflow

## First milestone

- Song/project library
- Lyrics editor
- Syllable and cadence analysis
- Phonetic-chain suggestions
- Apple Intelligence lyric actions
- Structured music-prompt builder
- Model manager foundation

## Dataset-driven Suno prompt engine

The Song Editor's "Fusion Builder" is a native port of the prompt-generation
system originally prototyped as a web app against the `nyuuzyou/suno`
Hugging Face dataset (659,788 songs). `Resources/MusicTags.tsv` bundles the
215,240 cleaned, spelling-corrected, categorized tags that survived that
mining pass; `TagDatabase` loads it once at runtime, `FusionRandomizer`
does rarity-weighted and category-balanced selection, `PromptRoleEngine`
assigns each tag a musical function (rhythm/harmony/instrumentation/vocal/
production/atmosphere/technique/texture/genre/arrangement), and
`SunoPromptGenerator` turns a selection into a Suno-ready POS/NEG prompt
pair under four distinct generation modes (Blended, Evolution, Hybrid,
Sectioned), each with its own linguistic architecture rather than a shared
template. See `Engine/` and `Data/` for the implementation, `Views/
FusionBuilderView.swift` for the UI.

## Requirements

- Xcode 26+
- iOS 27+
- Apple Intelligence features are available only on supported devices and configurations.

See Apple's Foundation Models documentation for the current model/runtime capabilities.
