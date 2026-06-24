import AppKit
import SwiftUI

final class PermissionOnboardingWindowController: NSWindowController {
    init() {
        let hostingView = NSHostingView(rootView: PermissionOnboardingView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lexi Permissions"
        window.center()
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PermissionOnboardingView: View {
    @State private var statuses = Dictionary(uniqueKeysWithValues: BuddyPermission.allCases.map { ($0, BuddyPermissions.status($0)) })

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 34, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Lexi")
                        .font(.title2.weight(.semibold))
                    Text("Lexi uses selected text, screen context, and your spoken question to explain what you're looking at.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Hold Option + Space, then release to explain highlighted text", systemImage: "text.cursor")
                Label("Hold Option + Command, then release to enter Buddy Capture", systemImage: "cursorarrow.motionlines")
                Label("Drag a region; release to send the screenshot and question", systemImage: "mic")
            }
            .font(.body)

            VStack(spacing: 10) {
                ForEach(BuddyPermission.allCases, id: \.self) { permission in
                    permissionRow(permission)
                }
            }

            Spacer(minLength: 0)

            if BuddyPermission.allCases.allSatisfy({ statuses[$0]?.isGranted == true }) {
                Label("All Lexi permissions are enabled.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("After enabling permissions in System Settings, click Re-check. Some changes may require restarting Lexi.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Re-check") {
                    refreshStatuses()
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .padding(28)
        .frame(width: 560, height: 520)
    }

    private func permissionRow(_ permission: BuddyPermission) -> some View {
        let status = statuses[permission] ?? BuddyPermissions.status(permission)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status.isGranted ? .green : .secondary)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title)
                    .font(.headline)
                Text(permission.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if status.isGranted {
                Text("Enabled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    Button(buttonTitle(for: permission, status: status)) {
                        BuddyPermissions.request(permission) { newStatus in
                            statuses[permission] = newStatus
                        }
                        BuddyPermissions.openSystemSettings(for: permission)
                    }
                    .buttonStyle(.bordered)

                    Button("Open Settings") {
                        BuddyPermissions.openSystemSettings(for: permission)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func buttonTitle(for permission: BuddyPermission, status: BuddyPermissionStatus) -> String {
        switch status {
        case .denied:
            return "Open"
        case .granted:
            return "Enabled"
        case .notDetermined:
            return permission == .accessibility ? "Request" : "Allow"
        }
    }

    private func refreshStatuses() {
        statuses = Dictionary(uniqueKeysWithValues: BuddyPermission.allCases.map { ($0, BuddyPermissions.status($0)) })
    }
}
