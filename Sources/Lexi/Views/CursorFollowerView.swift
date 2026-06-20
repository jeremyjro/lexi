import SwiftUI

struct CursorFollowerView: View {
    let state: CursorFollowerState
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0.0
    @State private var glowOpacity: Double = 0.3
    
    var body: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(state.color.opacity(glowOpacity))
                .frame(width: 32, height: 32)
                .blur(radius: 8)
            
            // Main circle
            Circle()
                .fill(state.color)
                .frame(width: 20, height: 20)
                .scaleEffect(pulseScale)
                .rotationEffect(.degrees(rotationAngle))
            
            // Inner dot
            if state == .idle {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
            
            // Thinking animation - rotating ring
            if state == .thinking || state == .processing {
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(rotationAngle))
            }
            
            // Success checkmark
            if state == .success {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Error indicator
            if state == .error {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: state) { oldValue, newValue in
            startAnimation()
        }
    }
    
    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = state == .idle ? 1.0 : (state == .thinking ? 1.2 : 1.1)
        }
        
        if state == .thinking || state == .processing {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
        
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            glowOpacity = state == .idle ? 0.3 : 0.6
        }
    }
}

enum CursorFollowerState {
    case idle
    case active
    case thinking
    case processing
    case success
    case error
    
    var color: Color {
        switch self {
        case .idle:
            return Color.blue.opacity(0.6)
        case .active:
            return Color.blue
        case .thinking:
            return Color.orange
        case .processing:
            return Color.purple
        case .success:
            return Color.green
        case .error:
            return Color.red
        }
    }
}

struct CursorFollowerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .frame(width: 200, height: 200)
            
            VStack(spacing: 30) {
                CursorFollowerView(state: .idle)
                CursorFollowerView(state: .active)
                CursorFollowerView(state: .thinking)
                CursorFollowerView(state: .processing)
                CursorFollowerView(state: .success)
                CursorFollowerView(state: .error)
            }
        }
    }
}