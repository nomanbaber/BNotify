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
        guard
            let url  = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any],
            let base = dict["BASE_URL"] as? String,
            let id   = dict["APP_ID"] as? String
        else {
            print("❌ [BNotify] Missing or invalid PushNotificationConfig.plist")
            return
        }
        baseURL     = base
        appId       = id
        isConfigured = true
        print("✅ [BNotify] Configuration loaded for APP_ID: \(id)")
    }

    /// Call this from your app (e.g. in onAppear)
    public func registerForPushNotifications() {
        loadConfig()
        guard isConfigured else {
            print("❌ [BNotify] Config missing, cannot register")
            return
        }

        Task { @MainActor in
            await requestPermissionAndRegister()
        }
    }

    @MainActor
    private func requestPermissionAndRegister() async {
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

    /// Forward into this from your AppDelegate
    public func didRegisterForRemoteNotifications(token: Data) {
        let hex = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("🔍 AppDelegate didRegister — forwarding to SDK")
        print("📲 [BNotify] Device Token:", hex)
        // (Test-mode skip backend)
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("🔍 AppDelegate didFail — forwarding to SDK")
        print("❌ [BNotify] APNs registration failed:", error.localizedDescription)
    }
}
