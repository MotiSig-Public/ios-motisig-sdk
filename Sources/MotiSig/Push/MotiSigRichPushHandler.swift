import Foundation
import UserNotifications

/// Helpers for **Notification Service Extension** targets that download a remote image and attach it
/// before iOS presents the notification banner.
///
/// Add a Notification Service Extension target in Xcode, link the `MotiSig` product, then in
/// `NotificationService.didReceive(_:withContentHandler:)` call ``handle(request:contentHandler:)``.
public enum MotiSigRichPushHandler {

    /// Downloads an image from the push payload (when present) and delivers modified content.
    public static func handle(
        request: UNNotificationRequest,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let best = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }

        guard let urlString = Self.extractImageURLString(from: request.content.userInfo),
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            contentHandler(best)
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { localURL, _, _ in
            defer { contentHandler(best) }
            guard let localURL else { return }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: localURL, to: dest)
                let att = try UNNotificationAttachment(identifier: "motisig-image", url: dest, options: nil)
                best.attachments = [att]
            } catch {
                // deliver without attachment
            }
        }
        task.resume()
    }

    /// URL string resolution. Priority: `_motisig.imageUrl` (MotiSig canonical), then `_richContent.image` (Expo relay),
    /// `fcm_options.image` (FCM relay), then flat `image` / `imageUrl` / `image_url`.
    public static func extractImageURLString(from userInfo: [AnyHashable: Any]) -> String? {
        if let m = userInfo["_motisig"] as? [String: Any] {
            for key in ["imageUrl", "image_url", "image"] {
                if let s = m[key] as? String,
                   !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
        }
        if let rc = userInfo["_richContent"] as? [String: Any],
           let s = rc["image"] as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        if let fcm = userInfo["fcm_options"] as? [String: Any],
           let s = fcm["image"] as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        for key in ["image", "imageUrl", "image_url"] {
            if let s = userInfo[key] as? String,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        return nil
    }
}
