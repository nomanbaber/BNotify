//
//  PushNotificationSDK.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation
import UserNotifications
import UIKit
import WebKit   // for userAgent extraction (unused in NSE code paths)

// MARK: - Shared config loader
struct BNotifyConfig {
    let baseURL: String
    let apiKey: String
    let projectId: String?
    let appId: String?
    let appGroupId: String?
    
    static func load(fromBundle bundle: Bundle = .main, plistName: String = "PushNotificationConfig") -> BNotifyConfig? {
        guard
            let url = bundle.url(forResource: plistName, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let base = dict["BASE_URL"] as? String,
            let key = dict["API_KEY"] as? String
        else {
            
            #if DEBUG
            print("❌ [BNotify] Missing/invalid \(plistName).plist in current target (app or NSE)")
            #endif
            return nil
        }
        let project = dict["PROJECT_ID"] as? String
        let app = dict["APP_ID"] as? String
        let appGroup = dict["APP_GROUP_ID"] as? String
        return BNotifyConfig(baseURL: base, apiKey: key, projectId: project, appId: app, appGroupId: appGroup)
    }
    
    // MARK: - App Group Config Management
    
    /// Save config to App Group container (called by main app)
    static func saveToAppGroup(_ config: BNotifyConfig, appGroupId: String? = nil) {
        let groupId = appGroupId ?? config.appGroupId ?? "group.com.bnotify.convex.testing.BNotifyClient"
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            print("❌ [BNotify] Could not access App Group container: \(groupId)")
            return
        }
        
        let configURL = containerURL.appendingPathComponent("bnotify_config.json")
        
        let configDict: [String: Any] = [
            "BASE_URL": config.baseURL,
            "API_KEY": config.apiKey,
            "PROJECT_ID": config.projectId ?? "",
            "APP_ID": config.appId ?? "",
            "APP_GROUP_ID": config.appGroupId ?? ""
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted])
            try jsonData.write(to: configURL)
            print("✅ [BNotify] Config saved to App Group: \(configURL.path)")
        } catch {
            print("❌ [BNotify] Failed to save config to App Group: \(error)")
        }
    }
    
    /// Load config from App Group container (used by NSE when plist not found)
    static func loadFromAppGroup(appGroupId: String? = nil) -> BNotifyConfig? {
        let groupId = appGroupId ?? "group.com.bnotify.convex.testing.BNotifyClient"
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            print("❌ [BNotify] Could not access App Group container: \(groupId)")
            return nil
        }
        
        let configURL = containerURL.appendingPathComponent("bnotify_config.json")
        
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("❌ [BNotify] Config file not found in App Group: \(configURL.path)")
            return nil
        }
        
        do {
            let jsonData = try Data(contentsOf: configURL)
            guard let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let base = dict["BASE_URL"] as? String,
                  let key = dict["API_KEY"] as? String else {
                print("❌ [BNotify] Invalid config format in App Group")
                return nil
            }
            
            let project = (dict["PROJECT_ID"] as? String)?.isEmpty == false ? dict["PROJECT_ID"] as? String : nil
            let app = (dict["APP_ID"] as? String)?.isEmpty == false ? dict["APP_ID"] as? String : nil
            let appGroup = (dict["APP_GROUP_ID"] as? String)?.isEmpty == false ? dict["APP_GROUP_ID"] as? String : nil
            
            print("✅ [BNotify] Config loaded from App Group")
            return BNotifyConfig(baseURL: base, apiKey: key, projectId: project, appId: app, appGroupId: appGroup)
        } catch {
            print("❌ [BNotify] Failed to load config from App Group: \(error)")
            return nil
        }
    }
    
    /// Smart loader: tries plist first, then App Group (for NSE)
    static func loadSmart(fromBundle bundle: Bundle = .main, plistName: String = "PushNotificationConfig", appGroupId: String? = nil) -> BNotifyConfig? {
        // First try to load from plist (main app)
        if let config = load(fromBundle: bundle, plistName: plistName) {
            return config
        }
        
        // If plist not found, try App Group (NSE)
        print("🔍 [BNotify] Plist not found, trying App Group...")
        return loadFromAppGroup(appGroupId: appGroupId)
    }
}

// MARK: - App Group Log Helper
private extension BNotifyExtensionSafe {
    static let logFileName = "bnotify_nse_api_log.txt"
    
    /// Get the App Group ID from config or use default
    static func getAppGroupId() -> String {
        // Try to get from config first
        if let config = BNotifyConfig.loadSmart() {
            return config.appGroupId ?? "group.com.bnotify.convex.testing.BNotifyClient"
        }
        // Fallback to default
        return "group.com.bnotify.convex.testing.BNotifyClient"
    }
    
    static func appendToLog(_ message: String) {
        let appGroupId = getAppGroupId()
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("❌ [BNotify] Could not access App Group container: \(appGroupId)")
            return
        }
        let logURL = containerURL.appendingPathComponent(logFileName)
        let logMsg = "[\(Date())] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let data = logMsg.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? logMsg.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Extension-safe helper (call this from your NSE)
public enum BNotifyExtensionSafe {
    /// Post a "delivered" event from either the main app or a Notification Service Extension.
    /// - Note: Uses smart loading - tries plist first, then App Group fallback (for NSE).
    public static func trackDeliveredEvent(from userInfo: [AnyHashable: Any],
                                           plistName: String = "PushNotificationConfig") {
        
        print("🚀 [BNotify] trackDeliveredEvent called")
        appendToLog("🚀 trackDeliveredEvent called with userInfo: \(userInfo)")
        
        // Extract notificationId (top-level or inside aps)
        let nid = (userInfo["notificationId"] as? String)
            ?? ((userInfo["aps"] as? [String: Any])?["notificationId"] as? String)
        
        // Extract token (top-level or inside aps)
        let token = (userInfo["token"] as? String)
            ?? ((userInfo["aps"] as? [String: Any])?["token"] as? String)
        
        print("🔍 [BNotify] Extracted notificationId: \(nid ?? "nil")")
        print("🔍 [BNotify] Extracted token: \(token ?? "nil")")
        appendToLog("🔍 Extracted notificationId: \(nid ?? "nil")")
        appendToLog("🔍 Extracted token: \(token ?? "nil")")

        // Check required fields
        guard let notificationId = nid, let deviceToken = token else {
            let msg = "❌ Missing required fields - notificationId: \(nid ?? "nil"), token: \(token ?? "nil")"
            print("❌ [BNotify] \(msg)")
            appendToLog(msg)
            return
        }

        // ✅ NEW: Use smart loader (tries plist first, then App Group)
        guard let config = BNotifyConfig.loadSmart(fromBundle: .main, plistName: plistName) else {
            let msg = "❌ Failed to load config from both plist and App Group"
            print("❌ [BNotify] \(msg)")
            appendToLog(msg)
            return
        }
        
        guard let baseURL = URL(string: config.baseURL) else {
            let msg = "❌ Invalid BASE_URL: \(config.baseURL)"
            print("❌ [BNotify] \(msg)")
            appendToLog(msg)
            return
        }
        
        guard let url = URL(string: "/api/notifications/track-event", relativeTo: baseURL) else {
            let msg = "❌ Failed to create API URL"
            print("❌ [BNotify] \(msg)")
            appendToLog(msg)
            return
        }
        
        print("✅ [BNotify] Config loaded successfully. API URL: \(url)")
        appendToLog("✅ Config loaded successfully. API URL: \(url)")
        
        let key = config.apiKey
        // Build payload with all required fields
        let body: [String: Any] = [
            "eventType": "received",
            "notificationId": notificationId,
            "token": deviceToken
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            print("✅ [BNotify] Request body created: \(body)")
            appendToLog("✅ Request body created: \(body)")
        } catch {
            let msg = "❌ Failed to serialize request body: \(error)"
            print("❌ [BNotify] \(msg)")
            appendToLog(msg)
            return
        }

        print("🌐 [BNotify] Starting API request to: \(url)")
        appendToLog("🌐 Starting API request to: \(url)")

        // Extension-safe session (no keychain/cookies/background tasks)
        URLSession(configuration: .ephemeral).dataTask(with: req) { data, resp, err in
            if let err = err {
                let msg = "❌ [BNotify] NSE delivered POST error: \(err.localizedDescription)"
                print(msg)
                appendToLog(msg)
            } else if let http = resp as? HTTPURLResponse {
                var msg = "📥 [BNotify] NSE delivered status: \(http.statusCode)"
                if let data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
                    msg += "\n📥 [BNotify] NSE delivered body:\n\(s)"
                }
                print(msg)
                appendToLog(msg)
            } else {
                let msg = "❓ [BNotify] Unexpected response type"
                print(msg)
                appendToLog(msg)
            }
        }.resume()
    }
}

@MainActor
public final class BNotifyManager {

    // If you ever want to call from NSE without importing BNotifyExtensionSafe directly,
    // you can still expose a proxy. But DO NOT call app-only code here.
    public static func trackDeliveredEvent(from userInfo: [AnyHashable: Any]) {
        BNotifyExtensionSafe.trackDeliveredEvent(from: userInfo)
    }

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
        guard let config = BNotifyConfig.load() else {
            print("❌ [BNotify] Missing or invalid PushNotificationConfig.plist")
            return
        }
        baseURL     = config.baseURL
        projectId   = config.projectId
        appId       = config.appId
        apiKey      = config.apiKey
        isConfigured = true
        
        // ✅ NEW: Save config to App Group for NSE access
        BNotifyConfig.saveToAppGroup(config)
        
        print("""
            ✅ [BNotify] Loaded:
               • BASE_URL:   \(config.baseURL)
               • PROJECT_ID: \(config.projectId ?? "nil")
               • APP_ID:     \(config.appId ?? "nil")
               • API_KEY:    \(String(config.apiKey.prefix(8)))…\(String(config.apiKey.suffix(4)))
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

    // MARK: – Analytics

    public func trackEvent(type: String,
                           userInfo: [AnyHashable: Any],
                           actionId: String? = nil) {
        
        print("🎯 [BNotify] trackEvent called - type: \(type), actionId: \(actionId ?? "nil")")
        
        // Ensure configuration is loaded (important for cold app starts)
        ensureConfigured()
        
        guard isConfigured, let apiClient = apiClient else {
            print("❌ [BNotify] Cannot track event - manager not configured")
            return
        }

        // Extract notificationId
        var nid: String? = nil
        if let top = userInfo["notificationId"] as? String {
            nid = top
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let apsNid = aps["notificationId"] as? String {
            nid = apsNid
        }

        // Extract token (if available in notification payload)
        var deviceToken: String? = nil
        if let token = userInfo["token"] as? String {
            deviceToken = token
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let apsToken = aps["token"] as? String {
            deviceToken = apsToken
        }

        print("📌 [BNotify] Extracted notificationId: \(nid ?? "nil")")
        print("📌 [BNotify] Extracted token: \(deviceToken ?? "nil")")

        // Use background task to ensure the network call completes
        withBGTask("bnotify.trackEvent.\(type)") { finish in
            apiClient.postEvent(type: type, notificationId: nid, actionId: actionId, token: deviceToken) {
                finish()
            }
        }
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

    // MARK: – Debug Helpers (app-only)
    
    /// Read NSE logs from App Group container (for debugging)
    public func readNSELogs() -> String? {
        guard let config = BNotifyConfig.loadSmart() else {
            print("❌ [BNotify] Could not load config to get App Group ID")
            return nil
        }
        
        let appGroupId = config.appGroupId ?? "group.com.bnotify.convex.testing.BNotifyClient"
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("❌ [BNotify] Could not access App Group container: \(appGroupId)")
            return nil
        }
        
        let logURL = containerURL.appendingPathComponent("bnotify_nse_api_log.txt")
        
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            print("📝 [BNotify] No NSE log file found at: \(logURL.path)")
            return "No logs found"
        }
        
        do {
            let logContent = try String(contentsOf: logURL, encoding: .utf8)
            print("📖 [BNotify] NSE logs read successfully (\(logContent.count) characters)")
            return logContent
        } catch {
            print("❌ [BNotify] Failed to read NSE logs: \(error)")
            return nil
        }
    }
    
    /// Clear NSE logs from App Group container
    public func clearNSELogs() {
        guard let config = BNotifyConfig.loadSmart() else {
            print("❌ [BNotify] Could not load config to get App Group ID")
            return
        }
        
        let appGroupId = config.appGroupId ?? "group.com.bnotify.convex.testing.BNotifyClient"
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("❌ [BNotify] Could not access App Group container: \(appGroupId)")
            return
        }
        
        let logURL = containerURL.appendingPathComponent("bnotify_nse_api_log.txt")
        
        do {
            if FileManager.default.fileExists(atPath: logURL.path) {
                try FileManager.default.removeItem(at: logURL)
                print("🗑️ [BNotify] NSE logs cleared successfully")
            } else {
                print("📝 [BNotify] No NSE log file to clear")
            }
        } catch {
            print("❌ [BNotify] Failed to clear NSE logs: \(error)")
        }
    }

    // MARK: – Helpers (app-only)
    // Keep app alive briefly for the network call (not used in NSE)
    private func withBGTask(_ name: String = "bnotify.trackEvent", _ work: (@escaping () -> Void) -> Void) {
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid
        }
        work {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid
            }
        }
    }

    // Ensure plist/client are ready even on cold start (app)
    private func ensureConfigured() {
        if !isConfigured { loadConfig() }
        if apiClient == nil,
           let base = baseURL, let project = projectId, let app = appId, let key = apiKey {
            apiClient = APIClient(baseURL: base, projectId: project, appId: app, apiKey: key)
        }
    }
}

// MARK: – Example AppDelegate integration
/*
 // Add this to your AppDelegate.swift:
 
 // MARK: – Tap / Dismiss / Action
 func userNotificationCenter(_ center: UNUserNotificationCenter,
 didReceive response: UNNotificationResponse,
 withCompletionHandler completionHandler: @escaping () -> Void) {
 let userInfo = response.notification.request.content.userInfo
 
 if let data = try? JSONSerialization.data(withJSONObject: userInfo, options: .prettyPrinted),
 let json = String(data: data, encoding: .utf8) {
 print("📬 didReceive response payload:\n\(json)")
 } else {
 print("📬 didReceive response payload:", userInfo)
 }
 
 var type = "clicked"
 var actionId = "clicked"
 
 if response.actionIdentifier == UNNotificationDismissActionIdentifier {
 type = "dismissed"
 actionId = "dismiss"
 } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
 type = "clicked"
 actionId = "clicked"
 } else {
 // Custom action (if you have any)
 type = "action"
 actionId = response.actionIdentifier
 }
 
 // 🔹 Track notification interaction
 BNotifyManager.shared.trackEvent(type: type, userInfo: userInfo, actionId: actionId)
 
 completionHandler()
 }
 */
