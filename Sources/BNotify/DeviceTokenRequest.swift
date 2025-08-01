//
//  DeviceTokenRequest.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation

import Foundation

public struct DeviceTokenRequest: Codable {
    public let deviceToken: String
    public let platform: String
    public let appId: String

    public init(deviceToken: String, platform: String = "iOS", appId: String) {
        self.deviceToken = deviceToken
        self.platform = platform
        self.appId = appId
    }
}
