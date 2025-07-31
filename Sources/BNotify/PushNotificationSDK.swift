//
//  BNotifyManager.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation
import UserNotifications
import UIKit

@MainActor // Ensures concurrency safety for static shared instance
public final class BNotifyManager: NSObject {
    
    public static let shared = BNotifyManager()
    private override init() {}
    
    private var apiClient: APIClient!
    private var appId: String!
    
    // Load PushNotificationConfig.plist from client app
    private func loadConfig() {
        guard let url = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let baseURL = dict["BASE_URL"] as? String,
              let appId = dict["APP_ID"] as? String else {
            fatalError("❌ PushNotificationConfig.plist missing or invalid.")
        }
        
        self.appId = appId
        self.apiClient = APIClient(baseURL: baseURL, appId: appId)
    }
    
    // Call this in SwiftUI App .onAppear or AppDelegate of client app
    public func registerForPushNotifications() {
        loadConfig()
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                print("Push permission denied")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    public func didRegisterForRemoteNotifications(token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device Token: \(tokenString)")
        
        // Send token to backend
        let request = DeviceTokenRequest(deviceToken: tokenString, platform: "iOS", appId: appId)
        apiClient.sendDeviceToken(request)
    }
    
    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ Failed to register: \(error.localizedDescription)")
    }
}

// MARK: Notification Delegate
extension BNotifyManager: UNUserNotificationCenterDelegate {
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .sound])
    }
    
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        print("Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }
}
