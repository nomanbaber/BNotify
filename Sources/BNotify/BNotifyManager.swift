//
//  BNotifyManager.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation
import UserNotifications
import UIKit

public final class BNotifyManager: NSObject {
    
    @MainActor public static let shared = BNotifyManager()
    private override init() {}
    
    private var apiClient: APIClient?
    private var appId: String?
    private var isConfigured = false
    
    // MARK: - Load Configuration
    private func loadConfig() {
        guard let url = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let baseURL = dict["BASE_URL"] as? String,
              let appId = dict["APP_ID"] as? String else {
            print("❌ [BNotify] PushNotificationConfig.plist is missing or invalid. Please add it to your project.")
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
        loadConfig()
        
        guard isConfigured else {
            print("❌ [BNotify] Cannot register for push notifications. Config is missing.")
            return
        }
        
        // We are already on the main actor, so no DispatchQueue.main.async needed
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard let self = self else { return }
            
            guard granted else {
                print("⚠️ [BNotify] Push notification permission denied by user.")
                return
            }
            
            // Use @MainActor here because this closure is not guaranteed on main thread
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    
    // MARK: - APNs Callbacks
    public func didRegisterForRemoteNotifications(token: Data) {
        guard isConfigured, let appId = self.appId, let apiClient = self.apiClient else {
            print("❌ [BNotify] Cannot send token. SDK is not configured properly.")
            return
        }

        // Already on the main actor because class is @MainActor
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token: \(tokenString)")

        // Send token to backend
        let request = DeviceTokenRequest(deviceToken: tokenString, platform: "iOS", appId: appId)
        apiClient.sendDeviceToken(request)
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        DispatchQueue.main.async {
            print("❌ [BNotify] Failed to register for push notifications: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Delegate
// MARK: - Notification Delegate
extension BNotifyManager: UNUserNotificationCenterDelegate {
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Call directly on the same thread → avoid async dispatch
        completionHandler([.alert, .sound])
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle the notification (safe, quick work only)
        print("🔔 [BNotify] Notification tapped: \(response.notification.request.content.userInfo)")
        
        // Call immediately to avoid data race
        completionHandler()
    }
}

