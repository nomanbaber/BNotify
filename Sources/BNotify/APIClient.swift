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
    private let appId: String

    public init(baseURL: String, appId: String, session: URLSession = .shared) {
        guard let url = URL(string: baseURL) else {
            fatalError("Invalid BASE_URL: \(baseURL)")
        }
        self.baseURL = url
        self.appId = appId
        self.session = session
    }

    /// Sends the device token to your `/device-token` endpoint
    public func sendDeviceToken(_ requestModel: DeviceTokenRequest) {
        let endpoint = baseURL.appendingPathComponent("device-token")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(requestModel)
        } catch {
            print("❌ [BNotify] Failed to encode DeviceTokenRequest:", error)
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [BNotify] Network error sending device token:", error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                print("❌ [BNotify] Unexpected response sending device token")
                return
            }
            if (200...299).contains(http.statusCode) {
                print("✅ [BNotify] Device token sent successfully (status: \(http.statusCode))")
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("❌ [BNotify] Failed to send device token, status: \(http.statusCode)\n\(body)")
            }
        }
        task.resume()
    }
}
