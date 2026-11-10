import SwiftUI

/// "Update Available": what's new in the versions you don't have, and how to install them.
struct UpdatePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let release: Release
    @State private var updates = UpdateChecker.shared
    @State private var showSteps = false

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

                    DisclosureGroup("How to Update", isExpanded: $showSteps) {
                        VStack(alignment: .leading, spacing: 10) {
                            step(1, "On your Mac, open Terminal in the project folder.")
                            step(2, "Run `git pull` then `xcodegen generate`")
                            step(3, "Plug in your iPhone, open Alarm.xcodeproj and press ⌘R.")
                            Text("Your alarms, to-dos and settings are kept.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .font(.headline)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let url = updates.updatePageURL {
                        Button {
                            openURL(url)
                        } label: {
                            Text("View on GitHub")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
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

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.orange))
            Text(text)
                .font(.subheadline)
        }
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
