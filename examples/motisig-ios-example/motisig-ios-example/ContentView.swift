import MotiSig
import SwiftUI

struct NotificationListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: NotificationsViewModel
    @State private var path = NavigationPath()
    @State private var motiSigPushEnabled = MotiSig.shared.isNotificationEnabled

    var body: some View {
        NavigationStack(path: $path) {
            listOrEmpty
                .navigationTitle("Notifications")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Enable or disable notifications")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: true, vertical: true)
                                Text("MotiSig server")
                                    .font(.caption2)
                                    .foregroundStyle(Color.secondary)
                            }
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { motiSigPushEnabled },
                                    set: { newValue in
                                        motiSigPushEnabled = newValue
                                        MotiSig.shared.setNotificationEnabled(newValue)
                                    }
                                )
                            )
                            .labelsHidden()
                            .tint(.accentColor)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Enable or disable MotiSig server notifications")
                        .accessibilityValue(motiSigPushEnabled ? "On" : "Off")
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let item = viewModel.notifications.first(where: { $0.id == id }) {
                        NotificationDetailView(item: item)
                    }
                }
        }
        .onChange(of: viewModel.selectedNotificationID) { _, newValue in
            if let id = newValue {
                path.append(id)
                viewModel.selectedNotificationID = nil
            }
        }
        .onAppear {
            Task { await viewModel.mergeDeliveredNotificationsFromSystem() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.mergeDeliveredNotificationsFromSystem() }
        }
    }

    @ViewBuilder
    private var listOrEmpty: some View {
        if viewModel.notifications.isEmpty {
            ContentUnavailableView(
                "No Notifications Yet",
                systemImage: "bell.slash",
                description: Text(Self.emptyNotificationsDescription)
            )
        } else {
            List(viewModel.notifications) { item in
                NavigationLink(value: item.id) {
                    NotificationRow(item: item)
                }
            }
            .listStyle(.plain)
        }
    }

    /// Unstyled `Text` source so `ContentUnavailableView`'s `description:` stays a plain `Text` (see Swift type-checking / overload resolution for `Text` chains).
    private static let emptyNotificationsDescription =
        "Push notifications received by the app will appear here.\n\n"
        + "The toolbar toggle controls MotiSig server delivery, not iOS notification permission."
}

private struct NotificationRow: View {
    let item: NotificationItem

    private var rowIconName: String {
        if item.receivedInForeground { return "bell.badge" }
        if item.sourcedFromDeliveredCenter { return "tray.full" }
        return "hand.tap"
    }

    private var rowIconColor: Color {
        if item.receivedInForeground { return .blue }
        if item.sourcedFromDeliveredCenter { return .secondary }
        return .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rowIconName)
                .font(.title3)
                .foregroundStyle(rowIconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "No title")
                    .font(.headline)
                    .lineLimit(1)

                if let body = item.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(NotificationReceivedTimeFormat.label(receivedAt: item.receivedAt, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
