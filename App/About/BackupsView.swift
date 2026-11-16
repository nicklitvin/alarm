import SwiftUI

/// Settings → About & Updates → Your Data: every backup
/// (one per day for two weeks) with a way to put it back.
struct DataSection: View {
    var body: some View {
        Section {
            NavigationLink {
                BackupsView()
            } label: {
                Label("Backups", systemImage: "clock.arrow.circlepath")
            }
        } header: {
            Text("Your Data")
        } footer: {
            Text("Alarmie keeps a backup of your alarms, to-dos, notes and settings for each of the last 14 days.")
        }
    }
}

struct BackupsView: View {
    @State private var backups: [DataBackup.Backup] = []
    @State private var chosen: DataBackup.Backup?
    @State private var restored = false

    var body: some View {
        List {
            Section {
                ForEach(backups) { backup in
                    Button { chosen = backup } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.body.weight(.medium))
                            Text(backup.summary.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("Restoring replaces your current alarms, to-dos, notes and settings. What you have now is backed up first, so you can switch back.")
            }
        }
        .overlay {
            if backups.isEmpty {
                ContentUnavailableView("No Backups Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("A backup is made whenever you change something."))
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .alert("Restore this backup?", isPresented: Binding(
            get: { chosen != nil }, set: { if !$0 { chosen = nil } }
        ), presenting: chosen) { backup in
            Button("Restore") {
                Backups.restore(backup)
                restored = true
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("\(backup.date.formatted(date: .abbreviated, time: .shortened)): \(backup.summary.text). Your current data is backed up first.")
        }
        .alert("Backup Restored", isPresented: $restored) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your alarms, to-dos and notes are back as they were.")
        }
    }

    private func reload() {
        Backups.backUpNow() // today's backup is always current
        backups = Backups.all
    }
}
