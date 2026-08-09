//
//  POPButtons.swift
//  ProofOfPath
//

import SwiftUI

// MARK: - Primary

struct POPPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled && !isLoading else { return }
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(POPColor.graphite)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(POPFont.cardTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(POPColor.graphite)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 50)
            .padding(.horizontal, fullWidth ? 0 : 22)
            .background(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .fill(POPColor.brandYellow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(POPColor.graphite.opacity(0.12), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(POPPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Secondary (outline)

struct POPSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var isEnabled: Bool = true
    var fullWidth: Bool = true
    var tint: Color = POPColor.graphite
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(POPFont.cardTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 50)
            .padding(.horizontal, fullWidth ? 0 : 20)
            .background(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .fill(POPColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1.4)
            )
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(POPPressStyle())
        .disabled(!isEnabled)
    }
}

// MARK: - Tertiary (text)

struct POPTextButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = POPColor.brandOrange
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(POPFont.calloutMedium)
            }
            .foregroundStyle(tint)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(POPPressStyle())
        .disabled(!isEnabled)
    }
}

// MARK: - Destructive row button

struct POPDestructiveButton: View {
    let title: String
    var icon: String = "trash"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: {
            Haptics.warning()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(POPFont.cardTitle)
            }
            .foregroundStyle(POPColor.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .fill(POPColor.dangerSoft)
            )
        }
        .buttonStyle(POPPressStyle())
    }
}

// MARK: - Small pill action

struct POPPillButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = POPColor.graphite
    var filled: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11.5, weight: .bold)) }
                Text(title).font(POPFont.captionMedium)
            }
            .foregroundStyle(filled ? POPColor.graphite : tint)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                Capsule().fill(filled ? POPColor.brandYellow : POPColor.surface)
            )
            .overlay(
                Capsule().strokeBorder(filled ? Color.clear : tint.opacity(0.3), lineWidth: 1.2)
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(POPPressStyle())
        .disabled(!isEnabled)
    }
}

// MARK: - Press feedback

struct POPPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Icon button (toolbar-ish)

struct POPIconButton: View {
    let systemName: String
    var tint: Color = POPColor.graphite
    var accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(POPColor.surface))
                .overlay(Circle().strokeBorder(POPColor.hairline, lineWidth: 1))
        }
        .buttonStyle(POPPressStyle())
        .accessibilityLabel(Text(accessibilityTitle))
    }
}
