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
        return BNotifyConfig(baseURL: base, apiKey: key, projectId: project, appId: app)
    }
}

// MARK: - App Group Log Helper
private extension BNotifyExtensionSafe {
    static let appGroupId = "group.com.yourcompany.bnotify" // <-- CHANGE to your App Group ID
    static let logFileName = "bnotify_nse_api_log.txt"
    
    static func appendToLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("❌ [BNotify] Could not access App Group container: \(appGroupId)")
            return
        }
        
        print("✅ [BNotify] App Group container found at: \(containerURL.path)")
        
        let logURL = containerURL.appendingPathComponent(logFileName)
        let logMsg = "[\(timestamp)] \(message)\n"
        
        do {
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                handle.seekToEndOfFile()
                if let data = logMsg.data(using: String.Encoding.utf8) {
                    handle.write(data)
                }
                handle.closeFile()
                print("✅ [BNotify] Appended to existing log file")
            } else {
                try logMsg.write(to: logURL, atomically: true, encoding: String.Encoding.utf8)
                print("✅ [BNotify] Created new log file at: \(logURL.path)")
            }
        } catch {
            print("❌ [BNotify] Failed to write to log file: \(error)")
        }
    }
}

// MARK: - Extension-safe helper (call this from your NSE)
public enum BNotifyExtensionSafe {
    /// Post a "delivered" event from either the main app or a Notification Service Extension.
    /// - Note: Reads PushNotificationConfig.plist from the **current target's** bundle (works in NSE).
    public static func trackDeliveredEvent(from userInfo: [AnyHashable: Any],
                                           plistName: String = "PushNotificationConfig") {
        
        print("🚀 [BNotify] trackDeliveredEvent called with userInfo keys: \(Array(userInfo.keys))")
        appendToLog("🚀 trackDeliveredEvent called with userInfo: \(userInfo)")
        
        // Extract notificationId (top-level or inside aps)
        let nid = (userInfo["notificationId"] as? String)
            ?? ((userInfo["aps"] as? [String: Any])?["notificationId"] as? String)
        
        print("🔍 [BNotify] Extracted notificationId: \(nid ?? "nil")")
        appendToLog("🔍 Extracted notificationId: \(nid ?? "nil")")

        // Load config using shared loader
        print("🔍 [BNotify] Loading config from plist: \(plistName)")
        appendToLog("🔍 Loading config from plist: \(plistName)")
        
        guard let config = BNotifyConfig.load(fromBundle: .main, plistName: plistName) else {
            let msg = "❌ Failed to load config from \(plistName).plist"
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
        // Build tiny payload
        var body: [String: Any] = ["eventType": "received"]
        if let nid { body["notificationId"] = nid }

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
    
    /// Helper function to read the NSE log file from the main app
    public static func readNSELog() -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("❌ [BNotify] Could not access App Group container: \(appGroupId)")
            return nil
        }
        
        let logURL = containerURL.appendingPathComponent(logFileName)
        
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            print("❌ [BNotify] Log file does not exist at: \(logURL.path)")
            return nil
        }
        
        do {
            let content = try String(contentsOf: logURL)
            print("✅ [BNotify] Successfully read log file (\(content.count) characters)")
            return content
        } catch {
            print("❌ [BNotify] Failed to read log file: \(error)")
            return nil
        }
    }
    
    /// Helper function to clear the NSE log file
    public static func clearNSELog() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
        let logURL = containerURL.appendingPathComponent(logFileName)
        try? FileManager.default.removeItem(at: logURL)
        print("🗑️ [BNotify] Cleared NSE log file")
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

        // Extract notificationId
        var nid: String? = nil
        if let top = userInfo["notificationId"] as? String {
            nid = top
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let apsNid = aps["notificationId"] as? String {
            nid = apsNid
        }

        // Optional token passthrough (if you include it)
        var Dtoken: String? = nil
        if let token = userInfo["token"] as? String {
            Dtoken = token
        } else if let aps = userInfo["aps"] as? [String: Any],
                  let apsToken = aps["token"] as? String {
            Dtoken = apsToken
        }

        print("📌 [BNotify] Extracted notificationId:", nid ?? "nil")

        apiClient?.postEvent(type: type, notificationId: nid, actionId: actionId, token: Dtoken)
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
    
    /// Helper function to read NSE logs from the main app
    public func readNSELogs() -> String? {
        return BNotifyExtensionSafe.readNSELog()
    }
    
    /// Helper function to clear NSE logs from the main app
    public func clearNSELogs() {
        BNotifyExtensionSafe.clearNSELog()
    }
}
