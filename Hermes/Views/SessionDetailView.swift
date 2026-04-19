import SwiftUI
import UniformTypeIdentifiers

/// Shows the full transcript for a single meeting session.
struct SessionDetailView: View {
    let session: MeetingSession
    @State private var showingExporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title.isEmpty ? session.startDate.formatted(date: .abbreviated, time: .shortened) : session.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Label(session.startDate.formatted(date: .long, time: .shortened), systemImage: "calendar")
                    Label(session.duration, systemImage: "clock")
                    Label("\(session.segments.count) segments", systemImage: "text.bubble")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Transcript
            if session.segments.isEmpty {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "text.bubble.slash",
                    description: Text("This session has no transcript segments.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.segments) { segment in
                            SegmentRowView(segment: segment)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportMarkdown()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export transcript as Markdown")
            }
        }
    }

    private func exportMarkdown() {
        let markdown = formatAsMarkdown()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Hermes-\(session.startDate.formatted(.iso8601.year().month().day())).md"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func formatAsMarkdown() -> String {
        var md = "# Meeting Transcript\n\n"
        md += "**Date:** \(session.startDate.formatted(date: .long, time: .shortened))\n"
        if let end = session.endDate {
            md += "**Duration:** \(session.duration)\n"
            md += "**Ended:** \(end.formatted(date: .long, time: .shortened))\n"
        }
        md += "\n---\n\n"

        for segment in session.segments {
            let speaker = segment.speaker == .me ? "**Me**" : "**Them**"
            md += "\(speaker): \(segment.text)\n\n"
        }
        return md
    }
}

struct SegmentRowView: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(segment.speaker == .me ? "Me" : "Them")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(segment.speaker == .me ? .blue : .orange)
                .frame(width: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.text)
                    .font(.body)

                if segment.startTime > 0 || segment.endTime > 0 {
                    Text(formatTimeRange(segment.startTime, segment.endTime))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatTimeRange(_ start: TimeInterval, _ end: TimeInterval) -> String {
        let fmt = { (t: TimeInterval) -> String in
            let m = Int(t) / 60
            let s = Int(t) % 60
            return String(format: "%d:%02d", m, s)
        }
        return "\(fmt(start)) – \(fmt(end))"
    }
}
