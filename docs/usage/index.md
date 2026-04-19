---
title: Usage
description: How to record, transcribe, and manage meeting sessions.
icon: material/play-circle
---

# Usage Guide

## Quick Start

1. **Launch Hermes** — it appears as a winged helmet icon in your menu bar. There is no Dock icon.
2. **Click the menu bar icon** to show the floating overlay panel.
3. **Select your microphone** from the dropdown at the top of the overlay.
4. **Start your call** in Zoom, Meet, Teams, FaceTime, or any app.
5. **Press the red record button** (or ++cmd+shift+r++) to start transcribing.
6. Watch the live transcript appear with **Me** and **Them** speaker labels.
7. **Stop** when you're done. The session is saved automatically.

## The Overlay

The overlay is a floating panel that stays on top of your call window.

### Expanded Mode

The full overlay (340 × 480) shows:

- **Mic picker** — dropdown to select your input device (disabled during recording)
- **Recording controls** — record, pause, resume, stop
- **Live transcript** — scrolling text with speaker labels and timestamps
- **History button** — clock icon to browse past sessions

### Collapsed Mode

Click the chevron to collapse the overlay into a tiny pill (48 × 64) showing just the Hermes icon and an expand button. The pill stays in the top-right corner and is draggable.

## Recording Controls

| State | Available Actions |
|---|---|
| **Idle** | :material-circle:{ style="color: red" } **Record** — start a new session |
| **Recording** | :material-pause:{ style="color: orange" } **Pause** · :material-stop:{ style="color: red" } **Stop** |
| **Paused** | :material-play:{ style="color: green" } **Resume** · :material-stop:{ style="color: red" } **Stop** |

### Global Hotkey

Press ++cmd+shift+r++ from any application to toggle recording on/off. No need to switch to the overlay.

## Speaker Labels

Hermes captures two separate audio streams:

- **Me** — your microphone input (your voice)
- **Them** — system audio output (everyone else on the call)

This gives you automatic speaker diarization without any ML-based speaker identification. Consecutive segments from the same speaker are merged into a single growing line.

## Session History

Click the :material-clock: clock icon in the overlay header to open the session history window.

From here you can:

- **Browse** all past sessions sorted by date
- **View** the full transcript of any session
- **Export** a session as Markdown
- **Delete** sessions you no longer need

## Tips for Best Results

!!! tip "Use headphones"
    Without headphones, your speakers bleed into the microphone and the same audio appears in both the "Me" and "Them" channels. Headphones eliminate this entirely.

!!! tip "First recording is slower"
    The first recording after launch takes a few seconds to start while WhisperKit loads the transcription model into memory. Subsequent recordings in the same session start instantly.

!!! info "Transcription window"
    Hermes buffers 10 seconds of audio before transcribing each chunk. This means there's a ~10 second delay between speech and transcript output. This window size produces significantly better accuracy than shorter intervals.

!!! info "Silence handling"
    When no one is speaking on the system audio channel, Hermes automatically suppresses transcription to prevent hallucinated text (Whisper's tendency to output "Thank you" or similar phrases on silence).

## Data Storage

All data is stored locally at:

```
~/Library/Application Support/Hermes/
```

This includes the SwiftData/SQLite database with your meeting sessions and transcript segments. No data is synced anywhere.
