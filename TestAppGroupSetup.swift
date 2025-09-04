import Foundation

// Add this test function to your client app to verify App Group setup
func testAppGroupSetup() {
    let appGroupId = "group.com.bnotify.convex.testing.BNotifyClient"
    
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
        print("✅ App Group container accessible at: \(containerURL.path)")
        
        // Test writing a file
        let testFile = containerURL.appendingPathComponent("test.txt")
        do {
            try "App Group working!".write(to: testFile, atomically: true, encoding: .utf8)
            print("✅ Successfully wrote test file to App Group")
            
            // Test reading the file
            let content = try String(contentsOf: testFile)
            print("✅ Successfully read from App Group: \(content)")
            
            // Clean up
            try FileManager.default.removeItem(at: testFile)
            print("✅ App Group setup is working correctly!")
            
        } catch {
            print("❌ Failed to write/read App Group file: \(error)")
        }
    } else {
        print("❌ Cannot access App Group container: \(appGroupId)")
        print("❌ Make sure you have:")
        print("   1. Added 'App Groups' capability to both app and NSE targets")
        print("   2. Added the App Group ID: \(appGroupId)")
        print("   3. Enabled the App Group in both targets")
    }
}

// Call this function in your app to test
// testAppGroupSetup()