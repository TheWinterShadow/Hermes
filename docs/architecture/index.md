---
title: Architecture
description: How Hermes captures audio and transcribes it locally.
icon: material/cog
---

# Architecture

## Overview

Hermes is a native Swift/SwiftUI macOS app that runs as a menu bar agent (`LSUIElement`). It captures two independent audio streams, transcribes them locally, and displays results in a floating overlay.

```
┌─────────────────┐     ┌──────────────────┐
│  System Audio    │     │   Microphone      │
│  (Zoom, Meet,   │     │   (Your voice)    │
│   Teams, etc.)  │     │                   │
└────────┬────────┘     └────────┬──────────┘
         │                       │
    CATap + IOProc          AVAudioEngine
         │                       │
         ▼                       ▼
┌────────────────────────────────────────────┐
│         AudioCaptureManager                │
│   Resamples to 16kHz mono Float32          │
│   Labels: .them          Labels: .me       │
└────────────────────┬───────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────┐
│       TranscriptionCoordinator             │
│   10-second buffer window                  │
│   Silence gate (.them only, RMS < 0.001)   │
│   Speaker turn merging                     │
└────────────────────┬───────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────┐
│         TranscriptionEngine                │
│   WhisperKit (large-v3, Apple Neural Engine)│
│   Batch transcribe(audioArray:)            │
└────────────────────┬───────────────────────┘
                     │
                     ▼
┌──────────────┐  ┌─────────────────┐
│  Overlay UI  │  │  SwiftData/     │
│  (NSPanel)   │  │  SQLite         │
└──────────────┘  └─────────────────┘
```

## Audio Capture

### System Audio — CATap

Hermes uses **Core Audio Taps** (CATap, macOS 14.2+) to capture system audio. This is the same mechanism professional audio tools use to tap into the system audio graph.

The setup follows a two-phase pattern:

1. **Create a `CATapDescription`** with `isExclusive = true` and an empty process list. This tells Core Audio to capture all system audio output (the semantics are inverted — "exclusive" means the process list is an exclusion list; empty exclusion list = capture everything).

2. **Create an aggregate device** with an empty sub-device list, then attach the tap post-creation via `kAudioAggregateDevicePropertyTapList`. This two-phase approach avoids connection errors that occur with single-dictionary setup.

3. **Register a C-function-pointer IOProc** via `AudioDeviceCreateIOProcID`. Block-based IOProcs with dispatch queues do not fire for aggregate devices with CATap — this is a Core Audio limitation.

4. **Read format from the tap** via `kAudioTapPropertyFormat`, not from the output device.

!!! note "Why not AVAudioEngine for system audio?"
    AVAudioEngine's `installTap()` is capped at ~100ms callback intervals, which is too coarse. CATap with a raw IOProc gives sample-accurate callbacks. AVAudioEngine works fine for mic capture though.

### Microphone — AVAudioEngine

The microphone is captured via standard `AVAudioEngine` with `installTap()` on the input node. The specific input device is set via `kAudioOutputUnitProperty_CurrentDevice` on the engine's audio unit.

### Cleanup Order

CATap resources must be cleaned up in a specific order to avoid crashes:

1. Stop the aggregate device
2. Destroy the IO proc
3. Destroy the aggregate device
4. Destroy the process tap

## Transcription

### WhisperKit

Hermes uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT license) with the `large-v3-v20240930_626MB` model running on Apple Neural Engine.

Key details:

- **Batch API only** — WhisperKit's streaming API is a Pro SDK feature. Hermes buffers 10 seconds of audio then calls `transcribe(audioArray:)`.
- **Input format** — 16kHz mono Float32 (resampled via `AudioBufferConverter`).
- **Special token stripping** — WhisperKit output contains tokens like `<|startoftranscript|>`, `<|en|>`, `<|endoftext|>`. These are stripped via regex post-processing.
- **No VAD chunking** — `chunkingStrategy: .vad` was removed because it caused special token leakage into output text.

### Silence Gate

When no audio is playing on the system channel, Whisper hallucinates common phrases ("Thank you", "Bye", etc.) from zero-filled buffers. Hermes applies an RMS-based silence gate (threshold 0.001) to the `.them` channel only.

The gate is not applied to the `.me` (microphone) channel because mic audio has very low RMS (0.00006–0.0005) even with real speech.

### Speaker Turn Merging

Consecutive transcript segments from the same speaker are merged into a single growing line in the UI, rather than creating a new line for each 10-second chunk. This produces natural-looking paragraphs instead of fragmented output.

## Persistence

Meeting sessions and transcript segments are stored via **SwiftData** (backed by SQLite) at:

```
~/Library/Application Support/Hermes/
```

The `MeetingSession` model stores session metadata (start time, end time, title) and its associated `TranscriptSegment` entries (speaker, text, timestamp).

## UI

| Component | Implementation |
|---|---|
| Menu bar icon | `NSStatusItem` with custom `HermesIcon` image asset |
| Floating overlay | `NSPanel` (`.nonactivatingPanel`, `.floating`) with SwiftUI hosted content |
| Collapse/expand | `OverlayState` ObservableObject bridges SwiftUI ↔ NSPanel, animated resize |
| Session history | Standard `NSWindow` with `NavigationSplitView` |

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI framework | SwiftUI + AppKit (NSPanel) |
| Audio (system) | CATap, Core Audio C API |
| Audio (mic) | AVAudioEngine |
| Transcription | WhisperKit (Apple Neural Engine) |
| Persistence | SwiftData / SQLite |
| Build system | XcodeGen → Xcode |
| CI/CD | GitHub Actions |
| Distribution | DMG (unsigned) |
