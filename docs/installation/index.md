---
title: Installation
description: Download or build Hermes from source.
icon: material/download
---

# Installation

## Requirements

Before installing Hermes, make sure your system meets these requirements:

| Requirement | Details |
|---|---|
| **macOS** | 14.4 (Sonoma) or later — required for Core Audio Taps |
| **Chip** | Apple Silicon (M1 or later) — required for WhisperKit / Neural Engine |
| **Disk space** | ~700 MB for the WhisperKit model (downloaded on first launch) |

## Download the DMG

The easiest way to install Hermes is from the GitHub releases page.

1. Go to the [latest release](https://github.com/TheWinterShadow/Hermes/releases/latest).
2. Download `Hermes-v*.dmg`.
3. Open the DMG and drag **Hermes.app** to your Applications folder (or run it from anywhere you like).

### Bypass Gatekeeper

Hermes is not signed with an Apple Developer certificate. On first launch, macOS will block it:

1. **Right-click** (or Control-click) on Hermes.app.
2. Select **Open** from the context menu.
3. Click **Open** in the dialog that appears.

You only need to do this once. After that, macOS remembers your choice.

Alternatively, remove the quarantine attribute from the terminal:

```bash
xattr -d com.apple.quarantine /Applications/Hermes.app
```

## Build from Source

If you prefer to build it yourself, you need [Xcode](https://developer.apple.com/xcode/) 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

### 1. Install XcodeGen

```bash
brew install xcodegen
```

### 2. Clone and build

```bash
git clone https://github.com/TheWinterShadow/Hermes.git
cd Hermes
xcodegen generate
xcodebuild \
    -project Hermes.xcodeproj \
    -scheme Hermes \
    -configuration Release \
    -arch arm64 \
    build
```

The built app will be at `build/Build/Products/Release/Hermes.app`.

### 3. Run it

```bash
open build/Build/Products/Release/Hermes.app
```

## Granting Permissions

On first recording, macOS will prompt you for two permissions:

### Microphone Access

A standard system dialog will appear asking for microphone permission. Click **OK**. This is required to capture your voice.

### Screen & System Audio Recording

CATap (Core Audio Taps) requires the **Screen & System Audio Recording** permission to capture audio from other applications.

1. Go to **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Find **Hermes** in the list and enable it.
3. You may need to restart Hermes after granting this permission.

!!! warning "Without this permission, Hermes can only capture your microphone"
    System audio capture (the "Them" channel) will not work until Screen & System Audio Recording is granted.

## WhisperKit Model

On first launch, WhisperKit automatically downloads the transcription model (`large-v3-v20240930_626MB`). This is a one-time ~626 MB download. The model is cached locally and reused for all future sessions.

The model runs entirely on Apple Neural Engine — no GPU or CPU fallback needed on Apple Silicon.
