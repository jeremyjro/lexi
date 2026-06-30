import SwiftUI

struct WelcomeFlowView: View {
    enum Page: Int, CaseIterable {
        case hello
        case gesture
        case permissions
        case allSet
    }

    let onFinish: () -> Void
    let onSkip: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var page: Page = .hello
    @State private var permissionStatuses: [BuddyPermission: BuddyPermissionStatus] = Dictionary(uniqueKeysWithValues: BuddyPermissions.requiredPermissions.map { ($0, BuddyPermissions.status($0)) })

    init(onFinish: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .id(page)
                .transition(.opacity)
            footer
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingPalette.background(for: colorScheme))
    }

    private var header: some View {
        HStack(alignment: .top) {
            Spacer()
            if let onSkip = onSkip {
                Button("Skip for now") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .hello:
            helloPage
        case .gesture:
            gesturePage
        case .permissions:
            permissionsPage
        case .allSet:
            allSetPage
        }
    }

    private var helloPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppMarkView(size: 68)

            VStack(alignment: .leading, spacing: 10) {
                Text("Hold, highlight, understand.")
                    .font(OnboardingTypography.display(42))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Lexi explains anything you’re reading — right where you are.")
                    .font(OnboardingTypography.body(18))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var gesturePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first move")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Hold ⌥ Space, highlight anything, then let go.")
                .font(OnboardingTypography.display(32))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            GestureDemoView()

            Text("Lexi follows your highlight, then gives you the short version — fast and calm.")
                .font(OnboardingTypography.body(17))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A couple of quick permissions")
                    .font(OnboardingTypography.display(30))
                    .foregroundStyle(.primary)
                Text("They help Lexi listen, read the spot you point to, and stay in step with your highlight.")
                    .font(OnboardingTypography.body(17))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PermissionOnboardingView { statuses in
                permissionStatuses = statuses
            }

            Text("You can change these anytime in System Settings.")
                .font(OnboardingTypography.body(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allSetPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppMarkView(size: 58)

            VStack(alignment: .leading, spacing: 10) {
                Text("You’re all set")
                    .font(OnboardingTypography.display(36))
                    .foregroundStyle(.primary)
                Text("A few gestures to keep close by:")
                    .font(OnboardingTypography.body(18))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                cheatSheetRow(title: "Explain highlighted text", detail: "Hold ⌥ Space")
                cheatSheetRow(title: "Ask about a screen region", detail: "Hold ⌥⌘ and drag")
                cheatSheetRow(title: "Ask out loud", detail: "Hold ⌃⌥ and speak")
                cheatSheetRow(title: "Inside an answer", detail: "Highlight a phrase and press →")
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func cheatSheetRow(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(detail)
                .font(OnboardingTypography.body(15))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                .fill(OnboardingPalette.surface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            backButton
            pageDots
            Spacer(minLength: 12)
            continueButton
        }
        .padding(.top, 24)
    }

    private var backButton: some View {
        Button("Back") {
            moveBack()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(page == .hello)
        .opacity(page == .hello ? 0 : 1)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases, id: \.self) { step in
                Circle()
                    .fill(step == page ? OnboardingPalette.accentEnd : OnboardingPalette.subtleStroke(for: colorScheme))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var continueButton: some View {
        let isLastPage = page == .allSet

        return Button(isLastPage ? "Start using Lexi" : "Continue") {
            moveForward()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.16, green: 0.14, blue: 0.13))
        )
    }

    private func moveBack() {
        guard let previous = Page(rawValue: max(0, page.rawValue - 1)) else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            page = previous
        }
    }

    private func moveForward() {
        switch page {
        case .hello:
            withAnimation(.easeInOut(duration: 0.22)) { page = .gesture }
        case .gesture:
            withAnimation(.easeInOut(duration: 0.22)) { page = .permissions }
        case .permissions:
            withAnimation(.easeInOut(duration: 0.22)) { page = .allSet }
        case .allSet:
            onFinish()
        }
    }
}
