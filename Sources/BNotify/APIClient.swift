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
}
