import Foundation
import UserNotifications
import UIKit

@MainActor
public final class BNotifyManager {
    public static let shared = BNotifyManager()
    private init() {}

    private var appId: String?
    private var baseURL: String?
    private var isConfigured = false

    private func loadConfig() {
        print("🔍 [BNotify] loadConfig()")
        guard
          let url = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let dict = try? PropertyListSerialization.propertyList(
              from: data, options: [], format: nil
            ) as? [String: Any],
          let base = dict["BASE_URL"] as? String,
          let id = dict["APP_ID"] as? String
        else {
          print("❌ [BNotify] Missing or invalid PushNotificationConfig.plist")
          return
        }
        baseURL = base
        appId    = id
        isConfigured = true
        print("✅ [BNotify] Configuration loaded for APP_ID: \(id)")
    }

    /// Call this from your App’s onAppear (or wherever you like).
    public func registerForPushNotifications() {
        loadConfig()
        guard isConfigured else {
            print("❌ [BNotify] Config missing, cannot register")
            return
        }

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                print("🔍 [BNotify] Permission granted:", granted)
                guard granted else {
                    print("⚠️ [BNotify] User denied push permission")
                    return
                }
                print("🔍 [BNotify] Registering with APNs…")
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                print("❌ [BNotify] Authorization error:", error)
            }
        }
    }

    /// Forward this from your AppDelegate
    public func didRegisterForRemoteNotifications(token: Data) {
        let hex = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token:", hex)

        // Skip backend in test-mode
        guard let id = appId, id != "app_12345",
              let base = baseURL else {
            print("⚠️ [BNotify] Skipping backend call (test mode)")
            return
        }
        let client = APIClient(baseURL: base, appId: id)
        client.sendDeviceToken(
          DeviceTokenRequest(deviceToken: hex, platform: "iOS", appId: id)
        )
    }

    /// Forward this from your AppDelegate
    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [BNotify] APNs registration failed:", error.localizedDescription)
    }
}
