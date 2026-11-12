import SwiftUI

/// "Update Available": what's new in the App Store version, with a button to update there.
struct UpdatePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let release: Release
    @State private var updates = UpdateChecker.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("Update Available")
                            .font(.largeTitle.weight(.bold))
                        Text("Version \(release.version) is ready. You have \(updates.installedVersionString).")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(newReleases) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text([item.version, item.title].compactMap { $0 }.joined(separator: " · "))
                                .font(.headline)
                            ReleaseNotes(notes: item.notes)
                        }
                    }

                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        openURL(updates.appStoreURL ?? URL(string: "itms-apps://apps.apple.com/account/updates")!)
                        dismiss()
                    } label: {
                        Label("Update in App Store", systemImage: "arrow.down.app")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    HStack {
                        Button("Skip This Version") {
                            updates.skip(release)
                            dismiss()
                        }
                        Spacer()
                        Button("Remind Me Later") { dismiss() }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .tint(.orange)
    }

    private var newReleases: [Release] {
        let pending = updates.pendingReleases
        return pending.isEmpty ? [release] : pending
    }
}

/// Shown once after updating: what changed since the version you used last.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    let releases: [Release]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's New")
                            .font(.largeTitle.weight(.bold))
                        if let latest = releases.first {
                            Text("Version \(latest.version)")
                                .font(.headline)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 40)

                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 10) {
                            if releases.count > 1 || release.title != nil {
                                Text([releases.count > 1 ? release.version : nil, release.title].compactMap { $0 }.joined(separator: " · "))
                                    .font(.title3.weight(.semibold))
                            }
                            ReleaseNotes(notes: release.notes)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .tint(.orange)
    }
}
