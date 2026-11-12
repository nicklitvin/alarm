import SwiftUI

/// The title row at the top of every tab: big title on the left, a short status on the right
/// ("Next in 7h 12m", "2 running"), then the tab's settings button. Replaces the system navigation
/// bar on tab roots, so switching tabs doesn't animate (or flicker) toolbar buttons.
struct TabHeader<Accessory: View>: View {
    let title: String?
    let tab: AppTab
    let detail: ((Date) -> String?)?
    let background: Color
    let accessory: () -> Accessory

    @State private var showSettings = false

    init(title: String?, tab: AppTab, detail: ((Date) -> String?)? = nil,
         background: Color = Color(.systemGroupedBackground),
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.tab = tab
        self.detail = detail
        self.background = background
        self.accessory = accessory
    }

    var body: some View {
        // Everything vertically centered, so the status text sits level with the gear.
        HStack(alignment: .center, spacing: 10) {
            if let title {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            if let detail {
                TimelineView(.everyMinute) { context in
                    if let text = detail(context.date) {
                        Text(text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            }
            accessory()
            SettingsButton { showSettings = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16) // room between the title and the content below
        .background(background)
        .sheet(isPresented: $showSettings) {
            TabSettingsView(tab: tab)
        }
    }
}

extension TabHeader where Accessory == EmptyView {
    init(title: String?, tab: AppTab, background: Color = Color(.systemGroupedBackground), detail: ((Date) -> String?)? = nil) {
        self.init(title: title, tab: tab, detail: detail, background: background) { EmptyView() }
    }
}

/// Gear button with a dot when an app update is waiting. The dot is always in the view tree
/// (just transparent) so the button never changes shape.
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.tertiarySystemFill)))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .opacity(UpdateChecker.shared.updateAvailable ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpdateChecker.shared.updateAvailable ? "Settings, update available" : "Settings")
    }
}
