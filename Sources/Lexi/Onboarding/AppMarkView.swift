import SwiftUI

/// The Lexi app mark used across onboarding — the shared brand monogram badge.
struct AppMarkView: View {
    let size: CGFloat

    var body: some View {
        LexiBrandMark(size: size)
    }
}
