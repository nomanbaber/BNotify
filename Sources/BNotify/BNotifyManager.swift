//
//  BNotifyManager.swift
//  BNotify
//
//  Debug version with thread checks & crash-proof handling
//

import Foundation
import UserNotifications
import UIKit

@MainActor
public final class BNotifyManager: NSObject {
    
    public static let shared = BNotifyManager()
    private override init() {}
    
    private var apiClient: APIClient?
    private var appId: String?
    private var isConfigured = false
    
    // MARK: - Load Configuration
    private func loadConfig() {
        print("🔍 [BNotify] loadConfig() on main:", Thread.isMainThread)
        
        guard let url = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let baseURL = dict["BASE_URL"] as? String,
              let appId = dict["APP_ID"] as? String else {
            print("❌ [BNotify] PushNotificationConfig.plist is missing or invalid. Please add it.")
            return
        }
        
        self.appId = appId
        self.apiClient = APIClient(baseURL: baseURL, appId: appId)
        self.isConfigured = true
        print("✅ [BNotify] Configuration loaded successfully for APP_ID: \(appId)")
    }
    
    // MARK: - Register for Push Notifications
    @MainActor
    public func registerForPushNotifications() {
        print("🔍 [BNotify] registerForPushNotifications() - main actor confirmed")

        loadConfig()

        guard isConfigured else {
            print("❌ [BNotify] Cannot register for push notifications. Config is missing.")
            return
        }

        UNUserNotificationCenter.current().delegate = self

        // requestAuthorization callback may NOT be on main actor → wrap it
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            // Ensure we switch back to MainActor
            Task { @MainActor in
                print("🔍 [BNotify] requestAuthorization callback - main actor confirmed")

                if granted {
                    print("🔍 [BNotify] Permission granted - registering for remote notifications")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    print("⚠️ [BNotify] Push notification permission denied by user.")
                }
            }
        }
    }


    // MARK: - APNs Callbacks
    public func didRegisterForRemoteNotifications(token: Data) {
        print("🔍 [BNotify] didRegisterForRemoteNotifications() on main:", Thread.isMainThread)
        
        guard isConfigured, let appId = self.appId, let apiClient = self.apiClient else {
            print("❌ [BNotify] Cannot send token. SDK is not configured properly.")
            return
        }
        
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token: \(tokenString)")
        
        // Send token to backend
        let request = DeviceTokenRequest(deviceToken: tokenString, platform: "iOS", appId: appId)
        apiClient.sendDeviceToken(request)
    }
    
    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [BNotify] Failed to register for push notifications: \(error.localizedDescription)")
    }
}

// MARK: - Notification Delegate
extension BNotifyManager: @preconcurrency UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("🔍 [BNotify] willPresentNotification() on main:", Thread.isMainThread)
        completionHandler([.alert, .sound])
    }
    
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        print("🔍 [BNotify] didReceiveNotification() on main:", Thread.isMainThread)
        print("🔔 [BNotify] Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }
}
