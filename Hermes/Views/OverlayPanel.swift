import AppKit
import Combine
import SwiftUI

/// Shared state between OverlayPanel and OverlayContentView for collapse/expand.
@MainActor
final class OverlayState: ObservableObject {
    @Published var isCollapsed = false
    @Published var recordingState: RecordingState = .idle

    /// The panel registers itself here so SwiftUI can trigger resize.
    weak var panel: OverlayPanel?

    private var cancellable: AnyCancellable?

    init() {
        cancellable = $isCollapsed
            .dropFirst()
            .sink { [weak self] collapsed in
                self?.panel?.animateToSize(collapsed: collapsed)
            }
    }
}

/// Floating panel that hovers above other windows (like Granola's overlay).
/// Uses NSPanel with .floating level so it stays on top of Zoom/Meet/Teams.
final class OverlayPanel: NSPanel {
    static let expandedWidth: CGFloat = 340
    static let expandedHeight: CGFloat = 480
    static let collapsedWidth: CGFloat = 48
    static let collapsedHeight: CGFloat = 64

    private let overlayState: OverlayState

    init(coordinator: TranscriptionCoordinator = TranscriptionCoordinator(),
         deviceManager: AudioDeviceManager = AudioDeviceManager(),
         overlayState: OverlayState = OverlayState(),
         actions: OverlayActions = OverlayActions()) {
        self.overlayState = overlayState
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.expandedWidth, height: Self.expandedHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        overlayState.panel = self
        configurePanel()
        positionPanel()
        setContent(coordinator: coordinator, deviceManager: deviceManager, overlayState: overlayState, actions: actions)
    }

    private func configurePanel() {
        title = "Hermes"
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        becomesKeyOnlyIfNeeded = true

        minSize = NSSize(width: 100, height: 36)
        maxSize = NSSize(width: 600, height: 1200)
    }

    /// Position at the right edge of the main screen, vertically centered.
    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - Self.expandedWidth - 16
        let y = screenFrame.midY - (Self.expandedHeight / 2)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func setContent(
        coordinator: TranscriptionCoordinator,
        deviceManager: AudioDeviceManager,
        overlayState: OverlayState,
        actions: OverlayActions
    ) {
        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                coordinator: coordinator,
                deviceManager: deviceManager,
                overlayState: overlayState,
                actions: actions
            )
        )
        contentView = hostingView
    }

    /// Animate between collapsed pill and expanded panel sizes.
    func animateToSize(collapsed: Bool) {
        let newWidth = collapsed ? Self.collapsedWidth : Self.expandedWidth
        let newHeight = collapsed ? Self.collapsedHeight : Self.expandedHeight

        // Keep the top-right corner anchored
        let currentFrame = frame
        let newX = currentFrame.maxX - newWidth
        let newY = currentFrame.maxY - newHeight
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)

        // Update style mask — remove resizable + closable when collapsed
        if collapsed {
            styleMask.remove(.resizable)
            styleMask.remove(.closable)
        } else {
            styleMask.insert(.resizable)
            styleMask.insert(.closable)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    func show() {
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
