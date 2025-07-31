//
//  BNotifyManager.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
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
    
    // Load PushNotificationConfig.plist from client app
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
    
    // Call this in SwiftUI App .onAppear or AppDelegate of client app
    public func registerForPushNotifications() {
        loadConfig()
        
        guard isConfigured else {
            print("❌ [BNotify] Cannot register for push notifications. Config is missing.")
            return
        }
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                print("⚠️ [BNotify] Push notification permission denied by user.")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    public func didRegisterForRemoteNotifications(token: Data) {
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

// MARK: Notification Delegate
extension BNotifyManager: @preconcurrency UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .sound])
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        print("🔔 [BNotify] Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }
}
