import SwiftUI
import AppKit

@main
struct CursorAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene since we're using a floating overlay
        Settings {
            EmptyView()
        }
    }
}