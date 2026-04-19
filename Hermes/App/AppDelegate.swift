import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

/// Central orchestrator for the Hermes app.
///
/// Owns all top-level subsystems — menu bar, overlay panel, audio capture,
/// transcription coordination, and session persistence — and wires them together.
/// Runs on `@MainActor` because it drives UI and uses SwiftData's main context.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - UI

    /// macOS menu bar status item (the app's only persistent UI anchor).
    private var statusItem: NSStatusItem!

    /// Floating overlay panel that displays the live transcript.
    private var overlayPanel: OverlayPanel!

    /// Session history window; lazily created on first open, reused thereafter.
    private var historyWindow: NSWindow?

    /// Reference to the registered Carbon global hotkey (Cmd+Shift+R).
    private var globalHotkeyRef: EventHotKeyRef?

    // MARK: - Subsystems

    /// Manages dual audio capture: CATap (system audio) + AVAudioEngine (mic).
    private let audioCaptureManager = AudioCaptureManager()

    /// Buffers audio, resamples to 16kHz, and drives WhisperKit transcription.
    private let transcriptionCoordinator = TranscriptionCoordinator()

    /// Enumerates available input devices for the mic picker dropdown.
    private let audioDeviceManager = AudioDeviceManager()

    /// Shared state between the panel window and its SwiftUI content (collapse, recording state).
    private let overlayState = OverlayState()

    /// The currently active recording session, or `nil` when idle.
    private var currentSession: MeetingSession?

    // MARK: - Lifecycle

    /// Called once at launch. Sets up every subsystem and kicks off WhisperKit model loading.
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupOverlayPanel()
        setupAudioPipeline()
        registerGlobalHotkey()

        // Model loading is async — transcription won't work until this completes,
        // but the UI is fully usable immediately (shows "model loading..." placeholder).
        Task { await transcriptionCoordinator.loadModel() }
    }

    // MARK: - Menu Bar

    /// Create the macOS menu bar status item with the Hermes icon and dropdown menu.
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let icon = NSImage(named: "HermesIcon")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Start Recording",
                action: #selector(toggleRecording),
                keyEquivalent: "r"
            )
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Show Overlay",
                action: #selector(toggleOverlay),
                keyEquivalent: "o"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Session History",
                action: #selector(showHistory),
                keyEquivalent: "h"
            )
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Hermes",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusItem.menu = menu
    }

    // MARK: - Overlay Panel

    /// Build the floating overlay panel, injecting all dependencies and action callbacks.
    /// The panel is created once and shown/hidden as needed.
    private func setupOverlayPanel() {
        let actions = OverlayActions(
            onStartRecording: { [weak self] in self?.startRecording() },
            onStopRecording: { [weak self] in self?.stopRecording() },
            onPauseRecording: { [weak self] in self?.pauseRecording() },
            onResumeRecording: { [weak self] in self?.resumeRecording() },
            onShowHistory: { [weak self] in self?.openHistory() }
        )
        overlayPanel = OverlayPanel(
            coordinator: transcriptionCoordinator,
            deviceManager: audioDeviceManager,
            overlayState: overlayState,
            actions: actions
        )
    }

    // MARK: - Audio Pipeline

    /// Wire the audio capture manager's output to the transcription coordinator.
    ///
    /// Audio samples arrive on background threads via `@Sendable` callback.
    /// We dispatch to `@MainActor` because `TranscriptionCoordinator` is MainActor-isolated.
    private func setupAudioPipeline() {
        let coordinator = transcriptionCoordinator
        audioCaptureManager.onAudioSamples = { @Sendable samples, speaker in
            Task { @MainActor in
                coordinator.appendSamples(samples, from: speaker)
            }
        }
    }

    // MARK: - Recording Actions

    /// Begin a new recording: reset coordinator state, create a SwiftData session,
    /// show the overlay, and start dual audio capture.
    private func startRecording() {
        transcriptionCoordinator.reset()
        startSession()
        overlayPanel.show()
        audioCaptureManager.micDeviceID = audioDeviceManager.selectedDeviceID
        do {
            try audioCaptureManager.startCapture()
            overlayState.recordingState = .recording
            updateMenuBarState()
        } catch {
            print("[Hermes] Failed to start capture: \(error)")
            overlayState.recordingState = .idle
            updateMenuBarState()
        }
    }

    /// Stop capture, flush remaining audio to transcription, persist session, reset state.
    private func stopRecording() {
        audioCaptureManager.stopCapture()
        transcriptionCoordinator.flush()
        stopSession()
        overlayState.recordingState = .idle
        updateMenuBarState()
    }

    /// Pause both mic and system audio capture without ending the session.
    private func pauseRecording() {
        audioCaptureManager.pauseCapture()
        overlayState.recordingState = .paused
        updateMenuBarState()
    }

    /// Resume both audio streams after a pause.
    private func resumeRecording() {
        audioCaptureManager.resumeCapture()
        overlayState.recordingState = .recording
        updateMenuBarState()
    }

    /// Sync the menu bar icon and first menu item title with current recording state.
    private func updateMenuBarState() {
        let isRecording = overlayState.recordingState != .idle

        if let menu = statusItem.menu, let item = menu.items.first {
            item.title = isRecording ? "Stop Recording" : "Start Recording"
        }
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: isRecording ? "waveform.circle.fill" : "waveform.circle",
                accessibilityDescription: "Hermes"
            )
        }
    }

    // MARK: - Session Persistence

    /// Create a new `MeetingSession` in SwiftData and insert it into the main context.
    private func startSession() {
        let session = MeetingSession(startDate: Date())
        let context = TranscriptStore.shared.container.mainContext
        context.insert(session)
        currentSession = session
        print("[Hermes] Session started")
    }

    /// Finalize the current session: set end date, copy transcript segments, save to disk.
    private func stopSession() {
        guard let session = currentSession else { return }
        session.endDate = Date()
        session.segments = transcriptionCoordinator.allSegments

        do {
            try TranscriptStore.shared.container.mainContext.save()
            print("[Hermes] Session saved (\(session.segments.count) segments)")
        } catch {
            print("[Hermes] Failed to save session: \(error)")
        }

        currentSession = nil
        transcriptionCoordinator.reset()
    }

    // MARK: - Global Hotkey (Cmd+Shift+R)

    /// Register a system-wide hotkey (Cmd+Shift+R) using the Carbon Event API.
    ///
    /// The Carbon EventHotKey API is the only way to register global hotkeys on macOS
    /// without accessibility permissions. The handler dispatches to MainActor via
    /// `DispatchQueue.main.async` since Carbon callbacks run on an unspecified thread.
    private func registerGlobalHotkey() {
        // 0x48524D53 = "HRMS" in ASCII — unique signature for this app's hotkey
        var hotkeyID = EventHotKeyID(signature: OSType(0x48524D53), id: 1)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            DispatchQueue.main.async {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.performToggleRecording()
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers, hotkeyID, GetApplicationEventTarget(), 0, &globalHotkeyRef)

        print("[Hermes] Global hotkey registered: Cmd+Shift+R")
    }

    // MARK: - Actions (menu / hotkey)

    /// Core recording toggle — called from menu item and global hotkey.
    func performToggleRecording() {
        switch overlayState.recordingState {
        case .idle:
            startRecording()
        case .recording, .paused:
            stopRecording()
        }
    }

    /// Menu bar action target for the Start/Stop Recording item.
    @objc private func toggleRecording(_ sender: NSMenuItem) {
        performToggleRecording()
    }

    /// Menu bar action target: toggle overlay panel visibility.
    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        if overlayPanel.isVisible {
            overlayPanel.hide()
            sender.title = "Show Overlay"
        } else {
            overlayPanel.show()
            sender.title = "Hide Overlay"
        }
    }

    /// Menu bar action target: open session history window.
    @objc private func showHistory(_ sender: NSMenuItem) {
        openHistory()
    }

    /// Open (or bring to front) the session history window.
    ///
    /// The window is created lazily on first call and reused for subsequent calls.
    /// Uses `NSHostingView` to embed the SwiftUI `SessionListView`.
    private func openHistory() {
        if let window = historyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let sessionListView = SessionListView()
            .modelContainer(TranscriptStore.shared.container)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hermes — Session History"
        window.contentView = NSHostingView(rootView: sessionListView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }
}
