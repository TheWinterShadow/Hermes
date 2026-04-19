import SwiftData
import SwiftUI

/// Shows a list of past meeting sessions with the ability to view full transcripts.
struct SessionListView: View {
    @Query(sort: \MeetingSession.startDate, order: .reverse) private var sessions: [MeetingSession]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSession: MeetingSession?

    var body: some View {
        NavigationSplitView {
            List(sessions, selection: $selectedSession) { session in
                SessionRowView(session: session)
                    .tag(session)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deleteSession(session)
                        }
                    }
            }
            .navigationTitle("Sessions")
            .frame(minWidth: 220)
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "waveform.slash",
                        description: Text("Recorded meetings will appear here.")
                    )
                }
            }
        } detail: {
            if let session = selectedSession {
                SessionDetailView(session: session)
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "text.bubble",
                    description: Text("Choose a session to view its transcript.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }

    private func deleteSession(_ session: MeetingSession) {
        if selectedSession == session {
            selectedSession = nil
        }
        modelContext.delete(session)
    }
}

struct SessionRowView: View {
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title.isEmpty ? sessionDateLabel : session.title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(session.startDate, style: .date)
                Text("·")
                Text(session.duration)
                Text("·")
                Text("\(session.segments.count) segments")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var sessionDateLabel: String {
        session.startDate.formatted(date: .abbreviated, time: .shortened)
    }
}
