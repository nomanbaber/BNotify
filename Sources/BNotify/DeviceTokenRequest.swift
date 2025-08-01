//
//  DeviceTokenRequest.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

//import Foundation
//
//public struct DeviceTokenRequest: Codable {
//    public let deviceToken: String
//    public let platform: String
//    public let appId: String
//
//    public init(deviceToken: String, platform: String = "iOS", appId: String) {
//        self.deviceToken = deviceToken
//        self.platform = platform
//        self.appId = appId
//    }
//}
import Foundation

public struct DeviceRegistrationRequest: Codable {
    public let uuid: String
    public let token: String
    public let project: String
    public let appId: String
    public let iosAppId: String
    public let ip: String
    public let os: String
    public let browser: String
    public let deviceType: String
    public let screenResolution: String
    public let timezone: String
    public let hardwareConcurrency: String
    public let deviceMemory: String
    public let platform: String
    public let userAgent: String
    public let country: String
    public let language: String
    public let version: String
    public let lat: String
    public let lng: String
}
