import SwiftUI

struct NotificationDetailView: View {
    let item: NotificationItem

    var body: some View {
        List {
            if let imageURL = Self.pushImageURL(from: item.userInfo) {
                Section("Image") {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                        case .failure:
                            Text("Could not load image")
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }

            Section("Message") {
                LabeledContent("Title", value: item.title ?? "—")
                if let body = item.body {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Body")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(body)
                    }
                }
            }

            Section("Metadata") {
                LabeledContent("Message ID", value: item.messageId ?? "—")
                LabeledContent("Received") {
                    Text(item.receivedAt, format: .dateTime)
                }
                LabeledContent("Delivery") {
                    Group {
                        if item.receivedInForeground {
                            Label("Foreground", systemImage: "bell.badge")
                                .foregroundStyle(.blue)
                        } else if item.sourcedFromDeliveredCenter {
                            Label("Notification Center", systemImage: "tray.full")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("User Tap", systemImage: "hand.tap")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if !item.userInfo.isEmpty {
                Section("Raw Payload") {
                    ForEach(item.userInfo.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: String(describing: item.userInfo[key] ?? "nil"))
                    }
                }
            }
        }
        .navigationTitle(item.title ?? "Notification")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private static let pushImageURLKeys: [String] = [
        "image",
        "imageUrl",
        "image_url",
        "fcm_notification_image_url",
        "gcm.notification.image",
    ]

    /// First HTTP(S) URL found in MotiSig canonical `_motisig`, relay keys, flat keys, or `ios_attachment_*_url` (Expo merge).
    static func pushImageURL(from userInfo: [String: Any]) -> URL? {
        var candidates: [String] = []
        if let m = userInfo["_motisig"] as? [String: Any] {
            for key in ["imageUrl", "image_url", "image"] {
                if let s = m[key] as? String {
                    candidates.append(s)
                }
            }
        }
        if let rc = userInfo["_richContent"] as? [String: Any],
           let s = rc["image"] as? String {
            candidates.append(s)
        }
        if let fcm = userInfo["fcm_options"] as? [String: Any],
           let s = fcm["image"] as? String {
            candidates.append(s)
        }
        for key in pushImageURLKeys {
            if let s = userInfo[key] as? String {
                candidates.append(s)
            }
        }
        for key in userInfo.keys.sorted() where key.hasPrefix("ios_attachment_") && key.hasSuffix("_url") {
            if let s = userInfo[key] as? String {
                candidates.append(s)
            }
        }
        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { continue }
            return url
        }
        return nil
    }
}
