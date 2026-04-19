---
title: Privacy
description: What data Hermes collects and where it goes.
icon: material/shield-check
---

# Privacy

## The Short Version

Hermes collects **nothing**. Your audio and transcripts **never leave your Mac**.

## What Hermes Does

- Captures system audio and microphone audio **locally** using macOS Core Audio APIs.
- Transcribes audio **on-device** using WhisperKit running on Apple Neural Engine.
- Stores transcripts **locally** in a SwiftData/SQLite database at `~/Library/Application Support/Hermes/`.

## What Hermes Does NOT Do

- **No network calls** — Hermes makes zero network requests during operation. The app has no network entitlements.
- **No analytics or telemetry** — no usage tracking, no crash reporting, no beacons.
- **No cloud storage** — transcripts are never uploaded anywhere.
- **No third-party services** — no OpenAI, no Google, no AWS, no anything.
- **No microphone access when not recording** — the mic is only active during an explicit recording session that you start and stop.

## WhisperKit Model Download

The only network activity is the **one-time download** of the WhisperKit transcription model (~626 MB) on first launch. This is fetched from the [Hugging Face Hub](https://huggingface.co/argmaxinc/whisperkit-coreml) and cached locally. After that, Hermes never needs the network again.

## Data Location

All persistent data lives at:

```
~/Library/Application Support/Hermes/
```

You can delete this folder at any time to remove all stored sessions and transcripts.

## Source Code

Hermes is open source. You can audit the code yourself at [github.com/TheWinterShadow/Hermes](https://github.com/TheWinterShadow/Hermes).
