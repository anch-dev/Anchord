# Anchord

**Anchord** is a native Apple-platform songwriting workbench built around Apple Intelligence and optional on-device open-source models.

The goal is simple: help writers preserve **cadence, pocket, phonetic shape, and intent** while turning ideas into structured prompts for music-generation tools.

## Architecture

- SwiftUI for the UI
- SwiftData for local projects and history
- Foundation Models for Apple Intelligence on supported devices
- A provider abstraction for future local Hugging Face/Core ML/MLX models
- No required server for the core songwriting workflow

## What works today

- Song library home screen and per-song workspace (Lyrics, Analysis, Prompt, Suno tabs)
- Rule-based syllable, stress and rhyme analysis (schemes, slant and internal rhyme, off-pocket lines)
- Dataset-driven Suno prompt engine (Fusion Builder) plus structured Direction in Prompt DNA
- Separate, editable POS / NEG / LYRICS with copy and share
- AI line rewrites, lyric analysis and prompt review (Apple Intelligence when available)
- Version history with restore and copy-as-new-song
- AI Settings: Apple Intelligence status, device-aware local model recommendations,
  real Hugging Face links, verified downloads

Not yet: a local inference engine (downloaded models are stored and verified but can't run yet),
a pronunciation-dictionary phonetic backend, and the macOS target. See `docs/ARCHITECTURE.md`.

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
