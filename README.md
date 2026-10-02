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

## Requirements

- Xcode 26+
- iOS 27+
- Apple Intelligence features are available only on supported devices and configurations.

See Apple's Foundation Models documentation for the current model/runtime capabilities.
