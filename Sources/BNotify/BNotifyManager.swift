import Foundation
import UserNotifications
import UIKit
import CoreTelephony   // for device model (optional)
import WebKit


public protocol BNotifyDelegate: AnyObject {
    /// Called when BNotify obtains the device token
    func bNotify(didRegisterDeviceToken token: String)
    /// Called if registration fails
    func bNotify(didFailWithError error: Error)
}

@MainActor
public final class BNotifyManager {
    public static let shared = BNotifyManager()
    private init() {}
    public weak var delegate: BNotifyDelegate?

    private var appId: String?
    private var baseURL: String?
    private var projectId: String?
    private var isConfigured = false
    private var apiClient: APIClient?

    private func loadConfig() {
        guard
            let url  = Bundle.main.url(forResource: "PushNotificationConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any],
            let base = dict["BASE_URL"] as? String,
            let id   = dict["APP_ID"] as? String
        else {
            print("❌ [BNotify] Missing or invalid PushNotificationConfig.plist")
            return
        }
        baseURL     = base
        appId       = id
        isConfigured = true
        print("✅ [BNotify] Configuration loaded for APP_ID: \(id)")
    }

    /// Call this from your app (e.g. in onAppear)
    public func registerForPushNotifications() {
        loadConfig()
        guard isConfigured else {
            print("❌ [BNotify] Config missing, cannot register")
            return
        }

        Task { @MainActor in
            await requestPermissionAndRegister()
        }
    }

    @MainActor
    private func requestPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("🔍 [BNotify] Permission granted:", granted)
            guard granted else {
                print("⚠️ [BNotify] User denied push permission")
                return
            }

            print("🔍 [BNotify] Registering with APNs…")
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("❌ [BNotify] Authorization error:", error)
        }
    }

    /// Forward into this from your AppDelegate
    public func didRegisterForRemoteNotifications(token: Data) {
        let hexToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [BNotify] Device Token:", hexToken)

        guard let id       = appId,
              let base     = baseURL,
              let project  = projectId,   // assuming you loaded this from your plist
              let bundleId = Bundle.main.bundleIdentifier
        else {
            print("⚠️ [BNotify] Missing config, skipping device registration")
            return
        }

        // 1) Build the request payload
        let uuid    = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let os      = "iOS " + UIDevice.current.systemVersion
        let device  = UIDevice.current.model
        let screen  = "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))"
        let tz      = TimeZone.current.identifier
        let cpu     = String(ProcessInfo.processInfo.processorCount)
        let memGB   = String(Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)) // GB
        let locale  = Locale.current
        let country = locale.regionCode ?? ""
        let lang    = locale.languageCode ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let ua      = WKWebView().value(forKey: "userAgent") as? String ?? "Unknown"
        let ip      = "0.0.0.0"    // placeholder (resolve via your own service)
        let lat     = ""           // if you have CLLocation, inject here
        let lng     = ""

        let req = DeviceRegistrationRequest(
            uuid: uuid,
            token: hexToken,
            project: project,
            appId: id,
            iosAppId: bundleId,
            ip: ip,
            os: os,
            browser: "Safari",
            deviceType: device,
            screenResolution: screen,
            timezone: tz,
            hardwareConcurrency: cpu,
            deviceMemory: memGB,
            platform: "ios",
            userAgent: ua,
            country: country,
            language: lang,
            version: version,
            lat: lat,
            lng: lng
        )

        // 2) Lazily create the client and send
        if apiClient == nil {
            apiClient = APIClient(
                baseURL: base,
                projectId: project,
                appId: id
            )
        }
        apiClient?.registerDevice(req)
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        print("🔍 AppDelegate didFail — forwarding to SDK")
        print("❌ [BNotify] APNs registration failed:", error.localizedDescription)
        
        delegate?.bNotify(didFailWithError: error)

    }
}
