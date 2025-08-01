//
//  BNotifyManager.swift
//  BNotify
//

import Foundation
import UserNotifications
import UIKit

@MainActor
public final class BNotifyManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Singleton (Main-actor isolated)
    public static let shared = BNotifyManager()

    // MARK: - Properties
    private var apiClient: APIClient?
    private var appId: String?
    private var isConfigured = false

    // MARK: - Init
    private override init() {
        super.init()
        print("✅ [BNotify] BNotifyManager initialized")
    }

    // MARK: - Load Config (APIClient Disabled)
    private func loadConfig() {
        print("🔍 [BNotify] loadConfig()")

        guard let url = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let baseURL = dict["BASE_URL"] as? String,
              let appId = dict["APP_ID"] as? String else {
            print("❌ [BNotify] PushNotificationConfig.plist missing or invalid")
            return
        }

        self.appId = appId
        self.isConfigured = true
        print("✅ [BNotify] Configuration loaded for APP_ID: \(appId)")

        // 🚫 Disable APIClient to isolate crash
        // self.apiClient = APIClient(baseURL: baseURL, appId: appId)
    }

    // MARK: - Register (Safe Mode)
    public func registerForPushNotifications() {
        loadConfig()

        guard isConfigured else {
            print("❌ [BNotify] Config missing, cannot register")
            return
        }

        print("🛑 [BNotify] Safe mode: skipping delegate & APNs registration")
    }

    // MARK: - APNs Callbacks
    public func didRegisterForRemoteNotifications(token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token: \(tokenString)")

        // Disabled backend call (test mode)
        print("⚠️ [BNotify] Test mode - skipping backend API call")
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [BNotify] Failed APNs registration: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("🔔 [BNotify] willPresent notification: \(notification.request.identifier)")
        completionHandler([.alert, .sound])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("🔔 [BNotify] didReceive notification: \(response.notification.request.identifier)")
        completionHandler()
    }
}
