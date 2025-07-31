//
//  DeviceTokenRequest.swift
//  BNotify
//
//  Created by Noman Babar on 31/07/2025.
//

import Foundation

internal struct DeviceTokenRequest: Codable {
    let deviceToken: String
    let platform: String
    let appId: String
}
