<p align="center">
  <img src="hermes.png" width="128" height="128" alt="Hermes logo">
</p>

<h1 align="center">Hermes</h1>

<p align="center">
  Local-first, privacy-focused meeting transcription for macOS.<br>
  No cloud services. No data leaves your device.
</p>

---

Hermes captures audio from your calls (Zoom, Meet, Teams, FaceTime — anything that outputs system audio) and your microphone simultaneously, transcribes both streams locally using [WhisperKit](https://github.com/argmaxinc/WhisperKit), and displays a live transcript in a floating overlay.

Think of it as a personal, offline [Granola](https://www.granola.ai/) — transcription only, no summarization (yet).

## Features

- **Dual-stream capture** — System audio (remote participants) via Core Audio Taps (CATap) and microphone (you) via AVAudioEngine. Free speaker diarization — "Me" vs "Them" — without any ML speaker identification.
- **On-device transcription** — WhisperKit running on Apple Neural Engine. Model: `large-v3-v20240930_626MB`. Nothing leaves your Mac.
- **Floating overlay** — A transparent panel that hovers above your call window. Collapses to a tiny pill icon when you don't need it.
- **Menu bar app** — Lives in your menu bar, no Dock icon.
- **Global hotkey** — `Cmd+Shift+R` to start/stop recording from anywhere.
- **Session history** — All transcripts are persisted locally via SwiftData. Browse past sessions and export as Markdown.
- **Mic input picker** — Choose which microphone to use from the overlay.
- **Pause/resume** — Pause and resume recording without ending the session.

## Requirements

- **macOS 14.4+** (Sonoma) — required for CATap (Core Audio Taps, introduced in 14.2)
- **Apple Silicon** (M1 or later) — required for WhisperKit / Neural Engine
- **Microphone permission** — macOS will prompt on first recording
- **Screen & System Audio permission** — required for CATap to capture system audio. Go to **System Settings → Privacy & Security → Screen & System Audio Recording** and enable Hermes.

## Installation

### From Release (DMG)

1. Download `Hermes-v1.0.0.dmg` from the [latest release](https://github.com/TheWinterShadow/Hermes/releases/latest).
2. Open the DMG and drag Hermes to Applications (or run it from anywhere).
3. Grant microphone and Screen & System Audio permissions when prompted.

### Build from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/TheWinterShadow/Hermes.git
cd Hermes
xcodegen generate
xcodebuild -project Hermes.xcodeproj -scheme Hermes -configuration Release build
```

The built app will be in `build/Build/Products/Release/Hermes.app`.

## Usage

1. **Launch Hermes** — it appears as an icon in your menu bar (no Dock icon).
2. **Click the menu bar icon** to show the floating overlay.
3. **Select your microphone** from the dropdown in the overlay header.
4. **Start a call** in Zoom, Meet, Teams, FaceTime, etc.
5. **Press the red record button** (or `Cmd+Shift+R`) to start transcribing.
6. The overlay shows a live transcript with speaker labels — **Me** (your mic) and **Them** (system audio).
7. **Pause** (yellow button) to temporarily stop, **Resume** (green button) to continue, or **Stop** (red square) to end the session.
8. **Collapse** the overlay to a small pill icon by clicking the chevron — expand it again anytime.
9. **Browse past sessions** by clicking the clock icon in the overlay header. Export any session as Markdown.

### Tips

- **Use headphones** for best results. Without them, your speakers bleed into the microphone and the same audio appears in both channels.
- The first recording takes a moment to start while WhisperKit loads the model. Subsequent recordings in the same session start instantly.
- Transcripts are stored locally at `~/Library/Application Support/Hermes/`.

## Privacy

Hermes is completely local. Audio is captured, transcribed, and stored on your Mac. There are no network calls, no analytics, no telemetry, no cloud anything. The app has no network entitlements.

## Architecture

| Component | Technology |
|---|---|
| Audio (system) | CATap → Aggregate Device → C IOProc callback |
| Audio (mic) | AVAudioEngine |
| Transcription | WhisperKit (Apple Neural Engine) |
| UI | SwiftUI + NSPanel overlay |
| Persistence | SwiftData / SQLite |
| Build | XcodeGen + Xcode |
| CI/CD | GitHub Actions → DMG release |

## License

Personal use. Not distributed via the App Store.
