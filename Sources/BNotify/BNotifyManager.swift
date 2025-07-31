//
//  BNotifyManager.swift
//  BNotify
//

import Foundation
import UserNotifications
import UIKit

@MainActor
public final class BNotifyManager: NSObject, UNUserNotificationCenterDelegate {

    public static let shared = BNotifyManager()
    private override init() {
        super.init()
        print("✅ [BNotify] BNotifyManager initialized")
    }

    private var apiClient: APIClient?
    private var appId: String?
    private var isConfigured = false

    // MARK: - Load Configuration
    private func loadConfig() {
        print("🔍 [BNotify] loadConfig() - main actor confirmed")
        
        guard let url = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let baseURL = dict["BASE_URL"] as? String,
              let appId = dict["APP_ID"] as? String else {
            print("❌ [BNotify] PushNotificationConfig.plist is missing or invalid.")
            return
        }
        
        self.appId = appId
        self.apiClient = APIClient(baseURL: baseURL, appId: appId)
        self.isConfigured = true
        print("✅ [BNotify] Configuration loaded for APP_ID: \(appId)")
    }

    // MARK: - Register for Push Notifications
    public func registerForPushNotifications() {
        print("🔍 [BNotify] registerForPushNotifications() - main actor confirmed")
        loadConfig()

        guard isConfigured else {
            print("❌ [BNotify] Cannot register: config missing")
            return
        }

        // Delay delegate setup slightly to avoid race with Apple's callbacks
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UNUserNotificationCenter.current().delegate = self
            print("🔍 [BNotify] Delegate set - main actor confirmed")

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    print("❌ [BNotify] requestAuthorization error: \(error.localizedDescription)")
                }

                if !granted {
                    print("⚠️ [BNotify] Push notification permission denied by user")
                    return
                }

                Task { @MainActor in
                    print("🔍 [BNotify] Authorization granted - calling registerForRemoteNotifications()")
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - APNs Callbacks
    public func didRegisterForRemoteNotifications(token: Data) {
        print("🔍 [BNotify] didRegisterForRemoteNotifications() - main actor confirmed")

        guard isConfigured, let appId = appId, let apiClient = apiClient else {
            print("❌ [BNotify] Cannot send token: SDK not configured")
            return
        }

        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token: \(tokenString)")

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
        // Call immediately to avoid threading issues
        completionHandler([.alert, .sound])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Only log and complete
        print("🔔 [BNotify] Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }
}
