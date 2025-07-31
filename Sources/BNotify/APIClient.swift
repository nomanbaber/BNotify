//
//  APIClient.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation

internal final class APIClient {
    private let baseURL: String
    private let appId: String
    private let session: URLSession
    
    init(baseURL: String, appId: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.appId = appId
        self.session = session
    }
    
    func sendDeviceToken(_ requestBody: DeviceTokenRequest) {
        guard let url = URL(string: "\(baseURL)/api/save-device-token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("❌ Encoding error: \(error.localizedDescription)")
            return
        }
        
        session.dataTask(with: request) { _, _, error in
            if let error = error {
                print("❌ Failed to send token: \(error.localizedDescription)")
            }
        }.resume()
    }
}
