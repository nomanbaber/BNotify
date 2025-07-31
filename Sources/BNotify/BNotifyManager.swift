//
//  BNotifyManager.swift
//  BNotify
//
//  Final version with delegate fixes and crash-proofing
//

import Foundation
import UserNotifications
import UIKit

@MainActor
public final class BNotifyManager: NSObject, UNUserNotificationCenterDelegate {
    
    // Singleton instance
    public static let shared = BNotifyManager()
    private override init() {
        super.init()
        print("✅ [BNotify] BNotifyManager initialized")
    }
    deinit {
        print("❌ [BNotify] BNotifyManager deallocated!")
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
        print("✅ [BNotify] Configuration loaded successfully for APP_ID: \(appId)")
    }
    
    // MARK: - Register for Push Notifications
    public func registerForPushNotifications() {
        print("🔍 [BNotify] registerForPushNotifications() - main actor confirmed")
        loadConfig()
        
        guard isConfigured else {
            print("❌ [BNotify] Cannot register for push notifications. Config is missing.")
            return
        }
        
        // Ensure delegate is set and stays alive
        UNUserNotificationCenter.current().delegate = self
        print("🔍 [BNotify] Delegate set - main actor confirmed")
        
        // Request authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                print("⚠️ [BNotify] Push notification permission denied by user.")
                return
            }
            
            // Switch back to main actor to register with APNs
            Task { @MainActor in
                print("🔍 [BNotify] Authorization granted - registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    // MARK: - APNs Callbacks
    public func didRegisterForRemoteNotifications(token: Data) {
        print("🔍 [BNotify] didRegisterForRemoteNotifications() - main actor confirmed")
        
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
    
    // MARK: - UNUserNotificationCenterDelegate (must be nonisolated)
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Call immediately on the same thread (avoid race conditions)
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
