import SwiftUI

/// Version info, update check and patch notes for every version. Opened from any tab's settings.
struct AboutView: View {
    @State private var updates = UpdateChecker.shared
    @State private var shownUpdate: Release?

    var body: some View {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.37, blue: 0.23)],
                                                         startPoint: .top, endPoint: .bottom))
                            )
                        Text("Alarmie")
                            .font(.title2.weight(.semibold))
                        Text("Version \(updates.installedVersionString) (\(updates.buildNumber))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    UpdateStatusRow { shownUpdate = $0 }
                    Button {
                        Task { await updates.check(userInitiated: true) }
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(updates.status == .checking)
                } header: {
                    Text("Updates")
                }

                Section {
                    ForEach(updates.changelog.releases) { release in
                        ReleaseRow(release: release, installed: updates.installedVersion,
                                   startExpanded: release.appVersion == updates.installedVersion)
                    }
                } header: {
                    Text("Patch Notes")
                }
            }
            .sheet(item: $shownUpdate) { UpdatePromptView(release: $0) }
            .navigationTitle("About & Updates")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.orange)
    }
}

private struct UpdateStatusRow: View {
    @State private var updates = UpdateChecker.shared
    let onView: (Release) -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if case .available(let release) = updates.status {
                Button("View") { onView(release) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var icon: some View {
        switch updates.status {
        case .checking: ProgressView()
        case .available: Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange).font(.title2)
        case .upToDate: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
        case .notOnAppStore: Image(systemName: "bag").foregroundStyle(.secondary).font(.title2)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.title2)
        case .idle: Image(systemName: "questionmark.circle").foregroundStyle(.secondary).font(.title2)
        }
    }

    private var title: String {
        switch updates.status {
        case .checking: "Checking…"
        case .available(let release): "Version \(release.version) Available"
        case .upToDate: "You're Up to Date"
        case .notOnAppStore: "Not From the App Store"
        case .failed: "Couldn't Check"
        case .idle: "Not Checked Yet"
        }
    }

    private var subtitle: String? {
        if case .failed(let message) = updates.status { return message }
        if updates.status == .notOnAppStore { return "This copy was installed from Xcode, so the App Store can't update it." }
        guard let checked = updates.lastChecked else { return nil }
        return "Last checked \(checked.formatted(.relative(presentation: .named)))"
    }
}

/// One version in the patch notes. Tap to expand.
private struct ReleaseRow: View {
    let release: Release
    let installed: AppVersion
    @State private var expanded: Bool

    init(release: Release, installed: AppVersion, startExpanded: Bool) {
        self.release = release
        self.installed = installed
        _expanded = State(initialValue: startExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ReleaseNotes(notes: release.notes)
                .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(release.version).font(.headline.monospacedDigit())
                    badge
                }
                Text([release.title, release.displayDate].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if let version = release.appVersion {
            if version == installed {
                tag("Installed", color: .green)
            } else if version > installed {
                tag("New", color: .orange)
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// Bulleted patch notes.
struct ReleaseNotes: View {
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(notes, id: \.self) { note in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text(note).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
