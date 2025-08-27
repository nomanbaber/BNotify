//
//  PushNotificationSDK.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation
import UserNotifications
import UIKit
import WebKit   // for userAgent extraction

@MainActor
public final class BNotifyManager {
    public static let shared = BNotifyManager()
    private init() {}

    // MARK: – Configured values
    private var baseURL: String?
    private var projectId: String?
    private var appId: String?
    private var apiKey: String?
    private var isConfigured = false

    // MARK: – Lazy API client
    private var apiClient: APIClient?

    // MARK: – Load the plist
    private func loadConfig() {
        print("🔍 [BNotify] loadConfig()")
        guard
            let url  = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any],
            let base      = dict["BASE_URL"]   as? String,
            let project   = dict["PROJECT_ID"] as? String,
            let app       = dict["APP_ID"]     as? String,
            let key       = dict["API_KEY"]    as? String
        else {
            print("❌ [BNotify] Missing or invalid PushNotificationConfig.plist")
            return
        }
        baseURL     = base
        projectId   = project
        appId       = app
        apiKey      = key
        isConfigured = true

        print("""
            ✅ [BNotify] Loaded:
               • BASE_URL:   \(base)
               • PROJECT_ID: \(project)
               • APP_ID:     \(app)
               • API_KEY:    \(String(key.prefix(8)))…\(String(key.suffix(4)))
            """)
    }

    // MARK: – Public API
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
                guard granted else { return }

                print("🔍 [BNotify] Registering with APNs…")
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                print("❌ [BNotify] Authorization error:", error)
            }
        }
    }

    // MARK: – APNs callback
    public func didRegisterForRemoteNotifications(token: Data) {
        let hexToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token:", hexToken)

        // ensure config values exist
        guard
            let base    = baseURL,
            let project = projectId,
            let app     = appId,
            let key     = apiKey
        else {
            print("❌ [BNotify] Missing config, cannot register device")
            return
        }

        // build the payload
        let uuid   = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let os     = "iOS " + UIDevice.current.systemVersion
        let device = UIDevice.current.model
        let screen = "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))"
        let tz     = TimeZone.current.identifier
        let cpu    = String(ProcessInfo.processInfo.processorCount)
        let memGB  = String(Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
        let locale = Locale.current
        let country = locale.regionCode ?? ""
        let language = locale.languageCode ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let userAgent: String = {
            let webView = WKWebView(frame: .zero)
            var ua = "Unknown"
            webView.evaluateJavaScript("navigator.userAgent") { result, _ in
                if let s = result as? String { ua = s }
            }
            return ua
        }()
        let ip = "0.0.0.0"   // replace with your lookup if needed
        let lat = ""
        let lng = ""

        let req = DeviceRegistrationRequest(
            uuid: uuid,
            token: hexToken,
            project: project,
            appId: app,
            iosAppId: Bundle.main.bundleIdentifier ?? "",
            ip: ip,
            os: os,
            browser: "Safari",
            deviceType: device,
            screenResolution: screen,
            timezone: tz,
            hardwareConcurrency: cpu,
            deviceMemory: memGB,
            platform: "ios",
            userAgent: userAgent,
            country: country,
            language: language,
            version: version,
            lat: lat,
            lng: lng
        )

        // lazy init client (injecting apiKey)
        if apiClient == nil {
            apiClient = APIClient(
                baseURL: base,
                projectId: project,
                appId: app,
                apiKey: key
            )
        }
        apiClient?.registerDevice(req)
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ [BNotify] APNs registration failed:", error.localizedDescription)
    }
    
    
    
      
    public func trackEvent(type: String, userInfo: [AnyHashable: Any], actionId: String? = nil) {
           
        
        var nid: String? = nil
        var Dtoken: String? = nil

            // 1. Top-level
            if let top = userInfo["notificationId"] as? String {
                nid = top
            }
            // 2. Inside aps
            else if let aps = userInfo["aps"] as? [String: Any],
                    let apsNid = aps["notificationId"] as? String {
                nid = apsNid
            }
        
        if let token = userInfo["token"] as? String {
            Dtoken = token
        }
        // 2. Inside aps
        else if let aps = userInfo["aps"] as? [String: Any],
                let apsToken = aps["token"] as? String {
            Dtoken = apsToken
        }

        print("📌 Extracted notificationId:", nid ?? "nil");
        
        apiClient?.postEvent(type: type, notificationId: nid, actionId: actionId , token: Dtoken)
      }
      
     public func registerCategories() {
          let openAction = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
          let category = UNNotificationCategory(
              identifier: "bnotify",
              actions: [openAction],
              intentIdentifiers: [],
              options: [.customDismissAction]
          )
          UNUserNotificationCenter.current().setNotificationCategories([category])
      }
}
