import Foundation
import AppKit
import ApplicationServices

class EnhancedContextAnalyzer {
    
    func analyzeAppContext(bundleIdentifier: String?, appName: String) -> AppCategory {
        guard let bundleId = bundleIdentifier else { return .unknown }
        
        // Social Media Apps
        let socialMediaApps = [
            "com.twitter.twitter", // Twitter/X
            "com.atebits.Tweetie2", // Twitter
            "com.facebook.facebook", // Facebook
            "com.instagram.instagram", // Instagram
            "com.linkedin.linkedin", // LinkedIn
            "com.toyopagroup.picaboo", // Snapchat
            "com.burbn.instagram", // Instagram
            "com.zuck.zuck", // Threads
            "com.reddit.reddit" // Reddit
        ]
        
        // Messaging Apps
        let messagingApps = [
            "com.apple.iChat", // Messages/iMessage
            "com.apple.MobileSMS", // Messages
            "com.facebook.Messenger", // Facebook Messenger
            "com.whatsapp.WhatsApp", // WhatsApp
            "com.hoccer.voip", // Telegram
            "com.discord", // Discord
            "com.slack.Slack", // Slack
            "us.zoom.xos", // Zoom
            "com.microsoft.teams", // Microsoft Teams
            "com.google.hangouts", // Google Hangouts
            "com.signal.Signal" // Signal
        ]
        
        // Code Editors
        let codeEditorApps = [
            "com.microsoft.VSCode", // Visual Studio Code
            "com.jetbrains.intellij", // IntelliJ IDEA
            "com.jetbrains.pycharm", // PyCharm
            "com.sublimetext.3", // Sublime Text
            "com.atom.Atom", // Atom
            "com.github.GitHubDesktop", // GitHub Desktop
            "com.fournova.Tower3", // Tower Git
            "com.gitup.co.gitup", // GitUp
            "org.gnu.Emacs", // Emacs
            "org.vim.MacVim", // MacVim
            "com.apple.dt.Xcode" // Xcode
        ]
        
        // Browsers
        let browserApps = [
            "com.google.Chrome", // Chrome
            "com.mozilla.firefox", // Firefox
            "com.apple.Safari", // Safari
            "com.microsoft.edgemac", // Edge
            "com.brave.Browser", // Brave
            "com.operasoftware.Opera", // Opera
            "com.vivaldi.Vivaldi" // Vivaldi
        ]
        
        // Document Apps
        let documentApps = [
            "com.microsoft.Word", // Word
            "com.microsoft.PowerPoint", // PowerPoint
            "com.microsoft.Excel", // Excel
            "com.apple.iWork.Pages", // Pages
            "com.apple.iWork.Keynote", // Keynote
            "com.apple.iWork.Numbers", // Numbers
            "com.adobe.Reader", // Adobe Reader
            "com.adobe.Acrobat.Pro" // Acrobat Pro
        ]
        
        // Email Apps
        let emailApps = [
            "com.apple.mail", // Mail
            "com.microsoft.Outlook", // Outlook
            "com.google.Gmail", // Gmail
            "com.mozyx.spark", // Spark
            "com.airmailapp.airmail", // Airmail
            "notnetairmail.Airmail" // Airmail 3
        ]
        
        // Notes Apps
        let notesApps = [
            "com.apple.Notes", // Notes
            "com.evernote.Evernote", // Evernote
            "com.notion.id", // Notion
            "com.agiletortoise.Drafts-OSX", // Drafts
            "com.yinxiang.Mac", // Evernote
            "com.microsoft.OneNote", // OneNote
            "com.readdle.smartmail2" // Spark
        ]
        
        // Terminal Apps
        let terminalApps = [
            "com.apple.Terminal", // Terminal
            "com.googlecode.iterm2", // iTerm2
            "co.zeit.hyper", // Hyper
            "com.googlecode.iterm2", // iTerm
            "org.gnu.Emacs", // Emacs (terminal mode)
            "net.sourceforge.XQuartz" // XQuartz
        ]
        
        if socialMediaApps.contains(bundleId) {
            return .socialMedia
        } else if messagingApps.contains(bundleId) {
            return .messaging
        } else if codeEditorApps.contains(bundleId) {
            return .codeEditor
        } else if browserApps.contains(bundleId) {
            return .browser
        } else if documentApps.contains(bundleId) {
            return .document
        } else if emailApps.contains(bundleId) {
            return .email
        } else if notesApps.contains(bundleId) {
            return .notes
        } else if terminalApps.contains(bundleId) {
            return .terminal
        } else {
            return .unknown
        }
    }
    
    func classifyContentType(
        surroundingText: String,
        appCategory: AppCategory,
        windowTitle: String?
    ) -> ContentType {
        let text = surroundingText.lowercased()
        
        // Check for code patterns
        let codePatterns = ["function", "class", "import", "return", "if", "else", "for", "while", "def", "var", "let", "const"]
        if codePatterns.contains(where: { text.contains($0) }) {
            return .code
        }
        
        // Check for technical documentation patterns
        let docPatterns = ["api", "endpoint", "parameter", "response", "request", "authentication", "documentation"]
        if docPatterns.contains(where: { text.contains($0) }) {
            return .documentation
        }
        
        // Check for business patterns
        let businessPatterns = ["revenue", "profit", "margin", "growth", "market", "sales", "customer", "quarterly"]
        if businessPatterns.contains(where: { text.contains($0) }) {
            return .business
        }
        
        // Check for slang/casual patterns
        let slangPatterns = ["tbh", "imo", "fr", "ngl", "rn", "lol", "lmao", "omg", "wtf"]
        if slangPatterns.contains(where: { text.contains($0) }) {
            return .slang
        }
        
        // Check for formal patterns
        let formalPatterns = ["hereby", "therefore", "furthermore", "consequently", "nevertheless", "regarding"]
        if formalPatterns.contains(where: { text.contains($0) }) {
            return .formal
        }
        
        // App-specific defaults
        switch appCategory {
        case .socialMedia:
            return .casual
        case .messaging:
            return .casual
        case .codeEditor:
            return .technical
        case .browser:
            return .mixed
        case .document:
            return .formal
        case .email:
            return .business
        case .notes:
            return .mixed
        case .terminal:
            return .technical
        case .unknown:
            return .mixed
        }
    }
    
    func extractSurroundingContext(
        selectedText: String,
        fullText: String,
        contextWindow: Int = 200
    ) -> String {
        guard let range = fullText.range(of: selectedText) else {
            return String(fullText.prefix(contextWindow))
        }
        
        let startIndex = max(fullText.startIndex, fullText.index(range.lowerBound, offsetBy: -contextWindow/2))
        let endIndex = min(fullText.endIndex, fullText.index(range.upperBound, offsetBy: contextWindow/2))
        
        return String(fullText[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func buildEnhancedAppContext(
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        selectedText: String?,
        surroundingText: String?,
        screenshotData: Data?
    ) -> EnhancedAppContext {
        
        let appCategory = analyzeAppContext(bundleIdentifier: bundleIdentifier, appName: appName)
        let contentType = classifyContentType(
            surroundingText: surroundingText ?? "",
            appCategory: appCategory,
            windowTitle: windowTitle
        )
        
        return EnhancedAppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            surroundingText: surroundingText,
            appCategory: appCategory,
            contentType: contentType,
            screenshotData: screenshotData
        )
    }
}