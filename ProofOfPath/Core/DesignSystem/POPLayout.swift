//
//  POPLayout.swift
//  ProofOfPath
//
//  Section headers, banners, empty states, key-value rows.
//

import SwiftUI

// MARK: - Screen header

struct POPScreenHeader: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = nil
    }

    init<T: View>(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> T) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(POPFont.display(28))
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(POPFont.callout)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Coin Strike feature artwork

/// Decorative, non-interactive scene art used to give deep workspace views a
/// consistent Coin Strike visual identity without affecting their data flow.
struct CoinStrikeFeatureBanner: View {
    let asset: String
    var height: CGFloat = 104

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [Color.clear, Color(hex: 0x061631).opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous)
                    .strokeBorder(POPColor.brandYellow.opacity(0.48), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Section header

struct POPSectionHeader: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(POPColor.warningSoft))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(POPFont.sectionTitle)
                    .foregroundStyle(POPColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                POPTextButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Banner

struct POPBanner: View {
    enum Kind {
        case info
        case success
        case warning
        case danger
        case neutral

        var color: Color {
            switch self {
            case .info: return POPColor.graphite
            case .success: return POPColor.success
            case .warning: return POPColor.brandOrange
            case .danger: return POPColor.danger
            case .neutral: return POPColor.inkSecondary
            }
        }

        var background: Color {
            switch self {
            case .info: return POPColor.yellowSoft
            case .success: return POPColor.successSoft
            case .warning: return POPColor.warningSoft
            case .danger: return POPColor.dangerSoft
            case .neutral: return POPColor.neutralSoft
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .danger: return "exclamationmark.octagon.fill"
            case .neutral: return "lightbulb"
            }
        }
    }

    let kind: Kind
    let message: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(kind.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(message)
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    POPTextButton(title: actionTitle, tint: kind.color, action: action)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(kind.background))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(kind.color.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Empty state

struct POPEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(POPColor.surfaceSunk)
                    .frame(width: compact ? 52 : 68, height: compact ? 52 : 68)
                Image(systemName: icon)
                    .font(.system(size: compact ? 22 : 28, weight: .medium))
                    .foregroundStyle(POPColor.brandOrange)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(compact ? POPFont.cardTitle : POPFont.title)
                    .foregroundStyle(POPColor.ink)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(POPFont.callout)
                    .foregroundStyle(POPColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            if let actionTitle, let action {
                POPPrimaryButton(title: actionTitle, fullWidth: false, action: action)
                    .padding(.top, 2)
            }
            if let secondaryTitle, let secondaryAction {
                POPTextButton(title: secondaryTitle, action: secondaryAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 20 : 30)
        .padding(.horizontal, 16)
    }
}

// MARK: - Key / value row

struct POPKeyValueRow: View {
    let label: String
    let value: String
    var valueColor: Color = POPColor.ink
    var icon: String?
    var isMultiline: Bool = false

    var body: some View {
        if isMultiline {
            VStack(alignment: .leading, spacing: 4) {
                labelView
                Text(value.popIsBlank ? "—" : value)
                    .font(POPFont.body)
                    .foregroundStyle(value.popIsBlank ? POPColor.inkTertiary : valueColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                labelView
                Spacer(minLength: 8)
                Text(value.popIsBlank ? "—" : value)
                    .font(POPFont.bodyMedium)
                    .foregroundStyle(value.popIsBlank ? POPColor.inkTertiary : valueColor)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var labelView: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(POPColor.inkTertiary)
            }
            Text(label)
                .font(POPFont.caption)
                .foregroundStyle(POPColor.inkSecondary)
        }
    }
}

// MARK: - Divider

struct POPDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(POPColor.hairlineSoft)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Stat tile

struct POPStatTile: View {
    let value: String
    let label: String
    var icon: String?
    var tint: Color = POPColor.graphite
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(POPFont.micro)
                    .foregroundStyle(POPColor.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(POPFont.numeric)
                .foregroundStyle(POPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(POPColor.inkTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
    }
}

// MARK: - Chip row (horizontal filter)

struct POPChip: View {
    let title: String
    var count: Int?
    var icon: String?
    let isSelected: Bool
    var tint: Color = POPColor.graphite
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(POPFont.captionMedium)
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isSelected ? POPColor.graphite.opacity(0.65) : POPColor.inkTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(isSelected ? POPColor.graphite.opacity(0.1) : POPColor.surfaceMuted))
                }
            }
            .foregroundStyle(isSelected ? POPColor.graphite : POPColor.inkSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(isSelected ? POPColor.brandYellow : POPColor.surface))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : POPColor.hairline, lineWidth: 1))
        }
        .buttonStyle(POPPressStyle())
    }
}

// MARK: - Toast overlay

struct POPToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    private var tint: Color {
        switch toast.style {
        case .success: return POPColor.success
        case .info: return POPColor.graphite
        case .warning: return POPColor.brandOrange
        case .error: return POPColor.danger
        }
    }

    private var icon: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = toast.detail {
                    Text(detail)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(POPColor.surface)
                .shadow(color: POPColor.graphite.opacity(0.14), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1.2)
        )
        .padding(.horizontal, 16)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Toast host

struct POPToastHost: ViewModifier {
    let toast: Toast?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    POPToastView(toast: toast, onDismiss: onDismiss)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                        .id(toast.id)
                        .task(id: toast.id) {
                            try? await Task.sleep(nanoseconds: 3_200_000_000)
                            if !Task.isCancelled { onDismiss() }
                        }
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: toast?.id)
    }
}

extension View {
    func popToast(_ toast: Toast?, onDismiss: @escaping () -> Void) -> some View {
        modifier(POPToastHost(toast: toast, onDismiss: onDismiss))
    }
}

// MARK: - Loading / inline note

struct POPInlineNote: View {
    let text: String
    var icon: String = "info.circle"
    var tint: Color = POPColor.inkSecondary

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1.5)
            Text(text)
                .font(POPFont.caption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
