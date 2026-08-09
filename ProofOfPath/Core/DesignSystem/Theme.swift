//
//  Theme.swift
//  ProofOfPath
//
//  Visual language: an investigation board without the gloom.
//  Sand paper, graphite ink, yellow highlighter, orange marker, green confirmation.
//

import SwiftUI

// MARK: - Palette

enum POPColor {

    // Brand anchors from the brief.
    static let brandYellow = Color(hex: 0xFFCC32)
    static let brandOrange = Color(hex: 0xFF821C)
    static let graphite     = Color(hex: 0x25231F)
    static let sand         = Color(hex: 0xFFF3CF)
    static let confirmGreen = Color(hex: 0x56AD55)

    // Surfaces
    static let canvas       = Color(hex: 0xFFFAEE)   // page background (paper)
    static let surface      = Color(hex: 0xFFFFFF)   // cards
    static let surfaceSunk  = Color(hex: 0xFFF3CF)   // sand blocks / table headers
    static let surfaceMuted = Color(hex: 0xF6F1E4)   // neutral filled rows

    // Ink
    static let ink          = Color(hex: 0x25231F)
    static let inkSecondary = Color(hex: 0x6E6A61)
    static let inkTertiary  = Color(hex: 0x9C978C)
    static let onDark       = Color(hex: 0xFFFAEE)

    // Lines
    static let hairline     = Color(hex: 0xE7DFC9)
    static let hairlineSoft = Color(hex: 0xF1EADA)

    // Semantic
    static let success      = Color(hex: 0x56AD55)
    static let warning      = Color(hex: 0xFF821C)
    static let danger       = Color(hex: 0xC7452C)
    static let neutral      = Color(hex: 0x8A857A)

    // Tints (soft backgrounds for badges / banners)
    static let successSoft  = Color(hex: 0xE7F3E6)
    static let warningSoft  = Color(hex: 0xFFEBD8)
    static let dangerSoft   = Color(hex: 0xFAE4DF)
    static let yellowSoft   = Color(hex: 0xFFF3CF)
    static let neutralSoft  = Color(hex: 0xF0EDE5)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - Typography

enum POPFont {
    static func display(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .default) }
    static let title      = Font.system(size: 22, weight: .bold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let cardTitle   = Font.system(size: 16, weight: .semibold)
    static let body        = Font.system(size: 15, weight: .regular)
    static let bodyMedium  = Font.system(size: 15, weight: .medium)
    static let callout     = Font.system(size: 14, weight: .regular)
    static let calloutMedium = Font.system(size: 14, weight: .medium)
    static let caption     = Font.system(size: 12.5, weight: .regular)
    static let captionMedium = Font.system(size: 12.5, weight: .semibold)
    static let micro       = Font.system(size: 11, weight: .semibold)
    static let numeric     = Font.system(size: 20, weight: .bold, design: .rounded)
    static let numericLarge = Font.system(size: 30, weight: .bold, design: .rounded)
    static let mono        = Font.system(size: 13, weight: .medium, design: .monospaced)
}

// MARK: - Metrics

enum POPMetrics {
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let chipRadius: CGFloat = 8

    static let gutter: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let stackGap: CGFloat = 12
    static let sectionGap: CGFloat = 22

    static let hairline: CGFloat = 1
    static let minTapTarget: CGFloat = 44
}

// MARK: - Card surface

struct POPCardStyle: ViewModifier {
    var padding: CGFloat = POPMetrics.cardPadding
    var background: Color = POPColor.surface
    var borderColor: Color = POPColor.hairline
    var radius: CGFloat = POPMetrics.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: POPMetrics.hairline)
            )
    }
}

extension View {
    func popCard(
        padding: CGFloat = POPMetrics.cardPadding,
        background: Color = POPColor.surface,
        borderColor: Color = POPColor.hairline,
        radius: CGFloat = POPMetrics.cardRadius
    ) -> some View {
        modifier(POPCardStyle(padding: padding, background: background, borderColor: borderColor, radius: radius))
    }

    /// Applies the app canvas colour behind a scrolling screen.
    func popScreenBackground() -> some View {
        self.background(POPColor.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    func popHidden(_ isHidden: Bool) -> some View {
        if isHidden { EmptyView() } else { self }
    }
}
