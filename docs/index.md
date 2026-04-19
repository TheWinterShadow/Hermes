---
title: Hermes
description: Local-first, privacy-focused meeting transcription for macOS.
hide:
  - navigation
  - toc
---

<p align="center">
  <img src="assets/hermes.png" width="128" height="128" alt="Hermes logo">
</p>

<h1 align="center">Hermes</h1>

<p align="center">
  <strong>Local-first, privacy-focused meeting transcription for macOS.</strong><br>
  No cloud services. No data leaves your device.
</p>

<p align="center">
  <a href="https://github.com/TheWinterShadow/Hermes/releases/latest">
    <img src="https://img.shields.io/github/v/release/TheWinterShadow/Hermes?style=flat-square" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2014.4%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-orange?style=flat-square" alt="Apple Silicon">
</p>

---

Hermes captures audio from your calls — Zoom, Google Meet, Microsoft Teams, FaceTime, or anything that outputs system audio — and your microphone simultaneously. It transcribes both streams locally using [WhisperKit](https://github.com/argmaxinc/WhisperKit) and displays a live transcript in a floating overlay that hovers above your call window.

Think of it as a personal, offline [Granola](https://www.granola.ai/) — transcription only, no data leaves your Mac, ever.

---

<div class="grid cards" markdown>

- :material-microphone: **Dual-Stream Capture**

    System audio (remote participants) via Core Audio Taps and microphone (you) via AVAudioEngine. Free speaker diarization — "Me" vs "Them" — with no ML speaker identification needed.

- :material-brain: **On-Device Transcription**

    WhisperKit running on Apple Neural Engine with the `large-v3` model. Nothing leaves your Mac. No API keys, no subscriptions.

- :material-monitor: **Floating Overlay**

    A transparent panel that hovers above your call window. Collapses to a tiny pill icon when you don't need it. Always on top, never in the way.

- :material-shield-lock: **Completely Private**

    No network calls, no analytics, no telemetry, no cloud anything. Audio is captured, transcribed, and stored on your Mac — period.

- :material-keyboard: **Global Hotkey**

    Start and stop recording from anywhere with `Cmd+Shift+R`. No need to switch windows.

- :material-history: **Session History**

    All transcripts are persisted locally via SwiftData. Browse past sessions and export as Markdown.

</div>

---

<div class="grid cards" markdown>

- [:material-download: **Installation**](installation/index.md)

    Download the DMG or build from source.

- [:material-play-circle: **Usage**](usage/index.md)

    Learn how to record, transcribe, and manage sessions.

- [:material-cog: **Architecture**](architecture/index.md)

    How Hermes captures audio and transcribes it.

- [:material-shield-check: **Privacy**](privacy/index.md)

    What data Hermes collects (nothing) and where it goes (nowhere).

</div>
