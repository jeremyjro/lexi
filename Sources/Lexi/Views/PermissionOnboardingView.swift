import SwiftUI

struct PermissionOnboardingView: View {
    let onStatusesChanged: ([BuddyPermission: BuddyPermissionStatus]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ViewModel

    init(onStatusesChanged: @escaping ([BuddyPermission: BuddyPermissionStatus]) -> Void = { _ in }) {
        self.onStatusesChanged = onStatusesChanged
        let initialStatuses = Dictionary(uniqueKeysWithValues: BuddyPermissions.requiredPermissions.map { ($0, BuddyPermissions.status($0)) })
        _viewModel = StateObject(wrappedValue: ViewModel(statuses: initialStatuses))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(BuddyPermissions.requiredPermissions, id: \.self) { permission in
                permissionRow(for: permission)
            }

            HStack {
                Button("Re-check") {
                    refreshStatuses()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                .fill(OnboardingPalette.surface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
        .onAppear {
            refreshStatuses()
        }
    }

    private func permissionRow(for permission: BuddyPermission) -> some View {
        let status = viewModel.statuses[permission] ?? BuddyPermissions.status(permission)
        let iconName = symbolName(for: permission)

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OnboardingPalette.mutedSurface(for: colorScheme))
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingPalette.accentEnd)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(benefitCopy(for: permission))
                    .font(OnboardingTypography.body(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                statusPill(for: status)

                if !status.isGranted {
                    Button("Allow") {
                        request(permission)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.20, green: 0.18, blue: 0.17))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func statusPill(for status: BuddyPermissionStatus) -> some View {
        Group {
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.32))
            case .denied:
                Label("Needs attention", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Color(red: 0.75, green: 0.34, blue: 0.24))
            case .notDetermined:
                Label("Not yet", systemImage: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.14 : 0.04))
        )
    }

    private func request(_ permission: BuddyPermission) {
        BuddyPermissions.request(permission) { newStatus in
            var updated = viewModel.statuses
            updated[permission] = newStatus
            viewModel.statuses = updated
            onStatusesChanged(updated)
        }
        BuddyPermissions.openSystemSettings(for: permission)
    }

    private func refreshStatuses() {
        var updated: [BuddyPermission: BuddyPermissionStatus] = [:]
        for permission in BuddyPermissions.requiredPermissions {
            updated[permission] = BuddyPermissions.status(permission)
        }
        viewModel.statuses = updated
        onStatusesChanged(updated)
    }

    private func symbolName(for permission: BuddyPermission) -> String {
        switch permission {
        case .accessibility:
            return "hand.tap"
        case .screenRecording:
            return "rectangle.on.rectangle"
        case .microphone:
            return "mic"
        case .speechRecognition:
            return "waveform"
        }
    }

    private func benefitCopy(for permission: BuddyPermission) -> String {
        switch permission {
        case .accessibility:
            return "So Lexi can read the text you highlight."
        case .screenRecording:
            return "So Lexi can see the area you point at."
        case .microphone:
            return "So you can just ask out loud."
        case .speechRecognition:
            return "So your spoken questions turn into text."
        }
    }
}

@MainActor
private final class ViewModel: ObservableObject {
    @Published var statuses: [BuddyPermission: BuddyPermissionStatus]

    init(statuses: [BuddyPermission: BuddyPermissionStatus]) {
        self.statuses = statuses
    }
}
