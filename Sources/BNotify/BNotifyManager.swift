//
//  BNotifyManager.swift
//  BNotify
//

import Foundation
import UserNotifications
import UIKit

@MainActor
public final class BNotifyManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Singleton (safe with @MainActor)
    public static let shared: BNotifyManager = BNotifyManager()

    private override init() {
        super.init()
        print("✅ [BNotify] BNotifyManager initialized")
    }

    private var apiClient: APIClient?
    private var appId: String?
    private var isConfigured = false

    // MARK: - Load Configuration
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
        self.apiClient = APIClient(baseURL: baseURL, appId: appId)
        self.isConfigured = true
        print("✅ [BNotify] Configuration loaded for APP_ID: \(appId)")
    }

    // MARK: - Register for Push Notifications
    public func registerForPushNotifications() {
        loadConfig()

        guard isConfigured else {
            print("❌ [BNotify] Config missing, cannot register")
            return
        }

        // Delay delegate setup slightly to avoid crashes with pending notifications
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            UNUserNotificationCenter.current().delegate = self
            print("🔍 [BNotify] Delegate set")
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ [BNotify] requestAuthorization error: \(error.localizedDescription)")
            }

            if !granted {
                print("⚠️ [BNotify] Push notification permission denied by user")
                return
            }

            // Register with APNs on main thread
            DispatchQueue.main.async {
                print("🔍 [BNotify] Authorization granted, calling registerForRemoteNotifications()")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - APNs Callbacks
    public func didRegisterForRemoteNotifications(token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token: \(tokenString)")

        guard isConfigured, let appId = appId, let apiClient = apiClient else {
            print("❌ [BNotify] Cannot send token, SDK not configured")
            return
        }

        let request = DeviceTokenRequest(deviceToken: tokenString, platform: "iOS", appId: appId)
        apiClient.sendDeviceToken(request)
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
        completionHandler([.alert, .sound])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("🔔 [BNotify] Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }
}
