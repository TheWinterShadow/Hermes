import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayPanel: OverlayPanel!
    private var historyWindow: NSWindow?
    private var globalHotkeyRef: EventHotKeyRef?

    private let audioCaptureManager = AudioCaptureManager()
    private let transcriptionCoordinator = TranscriptionCoordinator()
    private let audioDeviceManager = AudioDeviceManager()
    private let overlayState = OverlayState()
    private var currentSession: MeetingSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupOverlayPanel()
        setupAudioPipeline()
        registerGlobalHotkey()

        Task { await transcriptionCoordinator.loadModel() }
    }

    // MARK: - Menu Bar

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

    private func setupAudioPipeline() {
        let coordinator = transcriptionCoordinator
        audioCaptureManager.onAudioSamples = { @Sendable samples, speaker in
            Task { @MainActor in
                coordinator.appendSamples(samples, from: speaker)
            }
        }
    }

    // MARK: - Recording Actions

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

    private func stopRecording() {
        audioCaptureManager.stopCapture()
        transcriptionCoordinator.flush()
        stopSession()
        overlayState.recordingState = .idle
        updateMenuBarState()
    }

    private func pauseRecording() {
        audioCaptureManager.pauseCapture()
        overlayState.recordingState = .paused
        updateMenuBarState()
    }

    private func resumeRecording() {
        audioCaptureManager.resumeCapture()
        overlayState.recordingState = .recording
        updateMenuBarState()
    }

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

    private func startSession() {
        let session = MeetingSession(startDate: Date())
        let context = TranscriptStore.shared.container.mainContext
        context.insert(session)
        currentSession = session
        print("[Hermes] Session started")
    }

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

    private func registerGlobalHotkey() {
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

    @objc private func toggleRecording(_ sender: NSMenuItem) {
        performToggleRecording()
    }

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        if overlayPanel.isVisible {
            overlayPanel.hide()
            sender.title = "Show Overlay"
        } else {
            overlayPanel.show()
            sender.title = "Hide Overlay"
        }
    }

    @objc private func showHistory(_ sender: NSMenuItem) {
        openHistory()
    }

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
