import SwiftUI
import AppKit

struct BubbleView: View {
    @ObservedObject var viewModel: BubbleViewModel
    @State private var isVisible = false
    @State private var pulseAnimation = false
    @State private var isExpanded = false
    @State private var rotationAngle: Double = 0
    @State private var chatInput = ""
    @State private var isProcessing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.state {
            case .hidden:
                EmptyView()
                
            case .capturing:
                capturingView
                
            case .loading:
                loadingView
                
            case .streaming(let content):
                streamingResultView(content)
                
            case .result(let tabManager):
                tabbedResultView(tabManager, onClose: viewModel.onClose)
                
            case .error(let message):
                errorView(message)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .topLeading)
        .modifier(BackgroundModifier(state: viewModel.state))
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
            pulseAnimation = true
        }
        .onChange(of: viewModel.state.phase) { _, _ in
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
    
    private var capturingView: some View {
        HStack(spacing: 10) {
            // Animated pulsing dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulseAnimation ? 1.3 : 0.6)
                        .opacity(pulseAnimation ? 1.0 : 0.4)
                        .animation(
                            Animation.easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: pulseAnimation
                        )
                }
            }
            
            Text("Capturing...")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        )
        .onAppear {
            pulseAnimation = true
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            // Liquid glass loading animation
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                        .frame(width: 40 + CGFloat(index * 12), height: 40 + CGFloat(index * 12))
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                        .opacity(pulseAnimation ? 0.6 : 0.2)
                        .animation(
                            Animation.easeInOut(duration: 1.2)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: pulseAnimation
                        )
                }
                
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                    .opacity(pulseAnimation ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(),
                        value: pulseAnimation
                    )
            }
            .frame(height: 60)
            
            VStack(spacing: 4) {
                Text("Thinking")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                Text("Analyzing context...")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            if let onClose = viewModel.onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .onAppear {
            pulseAnimation = true
        }
    }
    
    private func streamingResultView(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with streaming indicator
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                        .opacity(pulseAnimation ? 1.0 : 0.6)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(),
                            value: pulseAnimation
                        )
                    
                    Text("Generating")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if let onClose = viewModel.onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
                .padding(.horizontal, 24)
            
            // Streaming content with proper scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Display thinking content in a different style
                        if content.hasPrefix("[Thinking]\n") {
                            let thinkingContent = String(content.dropFirst(10))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("🧠 Thinking...")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(thinkingContent)
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                                    .italic()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(content.isEmpty ? "No content received" : content)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundColor(.white)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: content) { oldValue, newValue in
                    print("🔄 Content changed from \(oldValue.count) to \(newValue.count) chars")
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("streaming-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
    
    private func resultView(_ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                    
                    Text("Explanation")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if let onClose = viewModel.onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Content
            ScrollView {
                Text(explanation)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(.white)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: isExpanded ? 750 : 350, alignment: .topLeading)
        }
        .padding(20)
    }
    
    private func tabbedResultView(_ manager: TabManager, onClose: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(manager.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isActive: manager.activeTabId == tab.id,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    manager.selectTab(tab)
                                }
                            },
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if manager.tabs.count == 1 {
                                        // Only one tab - close the entire popup
                                        viewModel.onClose?()
                                    } else {
                                        // Multiple tabs - just remove this tab
                                        manager.removeTab(tab)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            
            // Tab content
            if let activeTab = manager.activeTab {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                            
                            Text(activeTab.term)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            if let parent = activeTab.parentTerm {
                                Text("← \(parent)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation {
                                    isExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .contentShape(Circle())
                            
                            if let onClose = viewModel.onClose {
                                Button(action: onClose) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(Color.white.opacity(0.1)))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Content with text selection
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(activeTab.explanation)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundColor(.white)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                        }
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    
                    // Chat input for follow-up questions
                    HStack(spacing: 8) {
                        TextField("Ask a follow-up question...", text: $chatInput)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .disabled(isProcessing)
                            .focusable()
                            .onSubmit {
                                if !chatInput.isEmpty {
                                    isProcessing = true
                                    viewModel.onFollowUpPrompt?(chatInput) {
                                        isProcessing = false
                                    }
                                    chatInput = ""
                                }
                            }
                        
                        if isProcessing {
                            // Cool processing animation
                            HStack(spacing: 4) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(isProcessing ? 1.0 : 0.5)
                                        .opacity(isProcessing ? 1.0 : 0.5)
                                        .animation(
                                            Animation.easeInOut(duration: 0.6)
                                                .repeatForever()
                                                .delay(Double(index) * 0.2),
                                            value: isProcessing
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .id(manager.activeTabId) // Force refresh when tab changes
            } else {
                VStack(spacing: 12) {
                    Text("No tabs yet")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Select text to get started")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            }
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    
                    Text("Error")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                
                Spacer()
                
                if let onClose = viewModel.onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Error message
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.white)
                .lineSpacing(3)
            
            // Actions
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Check terminal for details")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                if let onRetry = viewModel.onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                            Text("Retry")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(20)
    }
}

// Custom button style with hover effect
struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.black.opacity(configuration.isPressed ? 0.1 : 0.05))
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Tab button component
struct TabButton: View {
    let tab: ExplanationTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Text(tab.term)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular, design: .default))
                        .lineLimit(1)
                        .foregroundColor(isActive ? .primary : .secondary)
                    
                    if isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.white.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(isActive ? 0.2 : 0.1), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Close tab")
            .padding(.leading, 2)
        }
    }
}

// Placeholder for OverlayWindow mentioned in main.swift
class OverlayWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.alphaValue = 0
    }
}

struct BackgroundModifier: ViewModifier {
    let state: BubbleState
    
    func body(content: Content) -> some View {
        if case .capturing = state {
            // Capturing state has its own styling, no background/border needed
            content
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.black.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}
