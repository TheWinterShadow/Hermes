import CoreAudio
import SwiftUI

/// Actions the overlay can trigger, provided by AppDelegate.
struct OverlayActions {
    var onStartRecording: () -> Void = {}
    var onStopRecording: () -> Void = {}
    var onPauseRecording: () -> Void = {}
    var onResumeRecording: () -> Void = {}
    var onShowHistory: () -> Void = {}
}

/// Recording state exposed to the overlay UI.
enum RecordingState {
    case idle
    case recording
    case paused
}

/// The SwiftUI content rendered inside the floating overlay panel.
struct OverlayContentView: View {
    @ObservedObject var coordinator: TranscriptionCoordinator
    @ObservedObject var deviceManager: AudioDeviceManager
    @ObservedObject var overlayState: OverlayState
    var actions: OverlayActions

    var body: some View {
        if overlayState.isCollapsed {
            collapsedPill
        } else {
            expandedPanel
        }
    }

    // MARK: - Collapsed Pill

    private var collapsedPill: some View {
        VStack(spacing: 6) {
            // App icon with status color
            Image("HermesIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(pillStatusColor)

            // Expand button
            Button {
                overlayState.isCollapsed = false
            } label: {
                Image(systemName: "chevron.down.2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pillStatusColor: Color {
        switch overlayState.recordingState {
        case .recording: .green
        case .paused: .yellow
        case .idle: .secondary
        }
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row 1: status + collapse + controls
            HStack(spacing: 8) {
                // Collapse button
                Button {
                    overlayState.isCollapsed = true
                } label: {
                    Image(systemName: "chevron.up.2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Collapse to pill")

                // Status
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                Text(statusText)
                    .font(.headline)

                Spacer()

                // Recording controls
                recordingControls

                // History button
                Button {
                    actions.onShowHistory()
                } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Session History")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Header row 2: mic picker
            HStack(spacing: 6) {
                Image(systemName: "mic")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $deviceManager.selectedDeviceID) {
                    Text("System Default")
                        .tag(nil as AudioDeviceID?)
                    ForEach(deviceManager.inputDevices) { device in
                        Text(device.name)
                            .tag(device.id as AudioDeviceID?)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .disabled(overlayState.recordingState != .idle)

                Spacer()

                Text(Date(), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider()

            // Transcript
            if coordinator.lines.isEmpty {
                VStack {
                    Spacer()
                    Text("Start recording to see the transcript here.")
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(coordinator.lines) { line in
                                TranscriptLineView(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: coordinator.scrollTrigger) { _, _ in
                        if let last = coordinator.lines.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusIcon: String {
        switch overlayState.recordingState {
        case .recording: "waveform.circle.fill"
        case .paused: "pause.circle.fill"
        case .idle: "waveform.circle"
        }
    }

    private var statusColor: Color {
        switch overlayState.recordingState {
        case .recording: .green
        case .paused: .yellow
        case .idle: .secondary
        }
    }

    private var statusText: String {
        switch overlayState.recordingState {
        case .recording: "Recording"
        case .paused: "Paused"
        case .idle: "Ready"
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch overlayState.recordingState {
        case .idle:
            Button {
                actions.onStartRecording()
            } label: {
                Image(systemName: "record.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Start Recording")

        case .recording:
            HStack(spacing: 6) {
                Button {
                    actions.onPauseRecording()
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .help("Pause")

                Button {
                    actions.onStopRecording()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop Recording")
            }

        case .paused:
            HStack(spacing: 6) {
                Button {
                    actions.onResumeRecording()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Resume")

                Button {
                    actions.onStopRecording()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop Recording")
            }
        }
    }
}

struct TranscriptLineView: View {
    @ObservedObject var line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.speaker == .me ? "Me" : "Them")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(line.speaker == .me ? .blue : .orange)
                .frame(width: 36, alignment: .trailing)

            Text(line.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// View model for a speaker turn in the transcript.
/// Text grows as new transcription windows arrive for the same speaker.
class TranscriptLine: Identifiable, ObservableObject {
    let id = UUID()
    let speaker: Speaker
    let timestamp: Date
    @Published var text: String

    init(speaker: Speaker, text: String, timestamp: Date) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }

    func append(_ newText: String) {
        text += " " + newText
    }
}
