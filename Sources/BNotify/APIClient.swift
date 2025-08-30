//
//  APIClient.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation

public class APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let projectId: String
    private let appId: String
    private let apiKey: String

    public init(baseURL: String,
                projectId: String,
                appId: String,
                apiKey: String,
                session: URLSession = .shared) {
        guard let url = URL(string: baseURL) else {
            fatalError("Invalid BASE_URL: \(baseURL)")
        }
        self.baseURL   = url
        self.projectId = projectId
        self.appId     = appId
        self.apiKey    = apiKey
        self.session   = session
    }

    public func registerDevice(_ requestModel: DeviceRegistrationRequest) {
        let endpoint = baseURL.appendingPathComponent("api/devices/register")
        print("🔗 [BNotify] Register endpoint URL:", endpoint.absoluteString)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(requestModel)
        } catch {
            print("❌ [BNotify] Failed to encode DeviceRegistrationRequest:", error)
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [BNotify] Network error registering device:", error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                print("❌ [BNotify] Unexpected response registering device")
                return
            }
            if (200...299).contains(http.statusCode) {
                print("✅ [BNotify] Device registered successfully (status: \(http.statusCode))")
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("❌ [BNotify] Device registration failed, status: \(http.statusCode)\n\(body)")
            }
        }.resume()
    }
    
    // APIClient.swift
    func postEvent(type: String,
                   notificationId: String?,
                   actionId: String?,
                   token: String? = nil,
                   completion: (() -> Void)? = nil) {

        let event = BNotifyEvent(
            eventType: type,
            notificationId: notificationId,
            token: token
        )

        guard let url = URL(string: "/api/notifications/track-event", relativeTo: baseURL) else {
            print("❌ [BNotify] Invalid URL for track-event")
            completion?(); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(event)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("❌ [BNotify] Event POST failed:", error.localizedDescription) }
            if let http = response as? HTTPURLResponse { print("📥 [BNotify] Event response status:", http.statusCode) }
            if let data = data, let str = String(data: data, encoding: .utf8) { print("📥 [BNotify] Event response body:\n\(str)") }
            completion?()
        }.resume()
    }

    
    
//    func postEvent(type: String, notificationId: String?, actionId: String? , token: String? ) {
//        let event = BNotifyEvent(
//            eventType: type,
//            notificationId: notificationId,
//            token: token
//            // actionId: actionId,
//            // timestamp: Int64(Date().timeIntervalSince1970 * 1000),
//            // appId: appId
//        )
//        
//        guard let url = URL(string: "/api/notifications/track-event", relativeTo: baseURL) else {
//            print("❌ [BNotify] Invalid URL for track-event")
//            return
//        }
//        
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpBody = try? JSONEncoder().encode(event)
//        
//        
//        
//        // 🔍 Log outgoing event
//        if let body = request.httpBody, let json = String(data: body, encoding: .utf8) {
//            print("📤 [BNotify] Sending event → \(url.absoluteString)\n\(json)")
//        }
//        
//        URLSession.shared.dataTask(with: request) { data, response, error in
//            if let error = error {
//                print("❌ [BNotify] Event POST failed:", error.localizedDescription)
//                return
//            }
//            
//            if let httpResponse = response as? HTTPURLResponse {
//                print("📥 [BNotify] Event response status:", httpResponse.statusCode)
//            }
//            
//            if let data = data, let str = String(data: data, encoding: .utf8) {
//                print("📥 [BNotify] Event response body:\n\(str)")
//            }
//        }.resume()
//    }
    
}
 
 
