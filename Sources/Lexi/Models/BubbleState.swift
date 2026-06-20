import Foundation
import Combine

enum BubbleState {
    case hidden
    case capturing  // Small popup at bottom showing capture animation
    case loading
    case streaming(String)  // Streaming result with partial content
    case result(TabManager) // Result with tabbed explanations
    case error(String)
    
    var isVisible: Bool {
        switch self {
        case .hidden: return false
        default: return true
        }
    }
    
    /// Stable identity for view transitions — streaming content updates don't change this.
    var phase: String {
        switch self {
        case .hidden: return "hidden"
        case .capturing: return "capturing"
        case .loading: return "loading"
        case .streaming: return "streaming"
        case .result: return "result"
        case .error: return "error"
        }
    }
}

@MainActor
final class BubbleViewModel: ObservableObject {
    @Published var state: BubbleState = .loading
    @Published var streamingContent: String = ""
    
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?
    var onTextSelected: ((String) -> Void)?
    var onFollowUpPrompt: ((String, @escaping () -> Void) -> Void)?
    
    func apply(
        state: BubbleState,
        onRetry: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onTextSelected: ((String) -> Void)? = nil,
        onFollowUpPrompt: ((String, @escaping () -> Void) -> Void)? = nil
    ) {
        self.state = state
        if case .streaming(let content) = state {
            streamingContent = content
        }
        if let onRetry { self.onRetry = onRetry }
        if let onClose { self.onClose = onClose }
        if let onTextSelected { self.onTextSelected = onTextSelected }
        if let onFollowUpPrompt { self.onFollowUpPrompt = onFollowUpPrompt }
    }
    
    func updateStreamingContent(_ content: String) {
        streamingContent = content
        state = .streaming(content)
    }
}

struct ExplanationTab: Identifiable, Equatable {
    let id = UUID()
    let term: String
    var explanation: String
    let parentTerm: String? // For tracking hierarchy
    
    static func == (lhs: ExplanationTab, rhs: ExplanationTab) -> Bool {
        lhs.id == rhs.id && lhs.term == rhs.term && lhs.explanation == rhs.explanation
    }
}

class TabManager: ObservableObject {
    @Published var tabs: [ExplanationTab] = []
    @Published var activeTabId: UUID?
    
    init() {
        // Initialize with empty state
    }
    
    func addTab(term: String, explanation: String, parentTerm: String? = nil) {
        let newTab = ExplanationTab(term: term, explanation: explanation, parentTerm: parentTerm)
        tabs.append(newTab)
        activeTabId = newTab.id
    }
    
    func removeTab(_ tab: ExplanationTab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.remove(at: index)
            // Set new active tab
            if activeTabId == tab.id {
                activeTabId = tabs.last?.id
            }
        }
    }
    
    func selectTab(_ tab: ExplanationTab) {
        activeTabId = tab.id
    }
    
    var activeTab: ExplanationTab? {
        tabs.first { $0.id == activeTabId }
    }
}