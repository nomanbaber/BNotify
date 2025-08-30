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

// MARK: - Extension-safe helper (call this from your NSE)
public enum BNotifyExtensionSafe {
    /// Post a "delivered" event from either the main app or a Notification Service Extension.
    /// - Note: Reads PushNotificationConfig.plist from the **current target's** bundle (works in NSE).
    public static func trackDeliveredEvent(from userInfo: [AnyHashable: Any],
                                           plistName: String = "PushNotificationConfig") {
        // Extract notificationId (top-level or inside aps)
        let nid = (userInfo["notificationId"] as? String)
            ?? ((userInfo["aps"] as? [String: Any])?["notificationId"] as? String)

        // Load config from this bundle (NSE has its own bundle)
        guard
            let cfgURL  = Bundle.main.url(forResource: plistName, withExtension: "plist"),
            let data    = try? Data(contentsOf: cfgURL),
            let dict    = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let baseStr = dict["BASE_URL"]   as? String,
            let key     = dict["API_KEY"]    as? String,
            let baseURL = URL(string: baseStr),
            let url     = URL(string: "/api/notifications/track-event", relativeTo: baseURL)
        else {
            #if DEBUG
            print("❌ [BNotify] Missing/invalid \(plistName).plist in current target (app or NSE)")
            #endif
            return
        }

        // Build tiny payload
        var body: [String: Any] = ["eventType": "delivered"]
        if let nid { body["notificationId"] = nid }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        // Extension-safe session (no keychain/cookies/background tasks)
        URLSession(configuration: .ephemeral).dataTask(with: req) { data, resp, err in
            #if DEBUG
            if let err = err {
                print("❌ [BNotify] NSE delivered POST error:", err.localizedDescription)
            } else if let http = resp as? HTTPURLResponse {
                print("📥 [BNotify] NSE delivered status:", http.statusCode)
                if let data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
                    print("📥 [BNotify] NSE delivered body:\n\(s)")
                }
            }
            #endif
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
}
