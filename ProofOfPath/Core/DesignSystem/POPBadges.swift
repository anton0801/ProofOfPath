//
//  POPBadges.swift
//  ProofOfPath
//
//  Status pills, confidence markers, meters — the "evidence board" vocabulary.
//

import SwiftUI

// MARK: - Status pill

struct POPBadge: View {
    let text: String
    var icon: String? = nil
    var color: Color = POPColor.neutral
    var soft: Color = POPColor.neutralSoft
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: compact ? 9 : 10, weight: .bold))
            }
            Text(text)
                .font(compact ? .system(size: 10, weight: .semibold) : POPFont.micro)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4.5)
        .background(Capsule().fill(soft))
        .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Confidence marker (three ticks)

struct ConfidenceMarker: View {
    let level: ConfidenceLevel
    var showLabel: Bool = true

    private var filled: Int {
        switch level {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    private static let barHeights: [CGFloat] = [7, 10, 13]

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2.5) {
                ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { pair in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(pair.offset < filled ? level.color : POPColor.hairline)
                        .frame(width: 5, height: pair.element)
                }
            }
            .frame(height: 13, alignment: .bottom)

            if showLabel {
                Text(level.title)
                    .font(POPFont.micro)
                    .foregroundStyle(POPColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Confidence \(level.title)"))
    }
}

// MARK: - Horizontal meter

struct POPMeter: View {
    /// 0...1
    let value: Double
    var tint: Color = POPColor.brandYellow
    var track: Color = POPColor.surfaceMuted
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(Int((max(0, min(1, value)) * 100).rounded())) percent"))
    }
}

// MARK: - Segmented meter for weights

struct WeightBar: View {
    /// Sum of assigned weights, in percent.
    let total: Double
    var height: CGFloat = 10

    private var clamped: Double { max(0, min(150, total)) }

    private var tint: Color {
        if abs(total - 100) < 0.01 { return POPColor.success }
        if total > 100 { return POPColor.danger }
        return POPColor.brandOrange
    }

    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(POPColor.surfaceMuted)
                Capsule()
                    .fill(tint)
                    .frame(width: min(1, clamped / 100) * fullWidth)
                // 100% marker
                Rectangle()
                    .fill(POPColor.graphite.opacity(0.35))
                    .frame(width: 1.5, height: height + 4)
                    .offset(x: fullWidth - 1)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Progress ring

struct POPProgressRing: View {
    /// 0...1
    let value: Double
    var size: CGFloat = 42
    var lineWidth: CGFloat = 5
    var tint: Color = POPColor.brandOrange

    var body: some View {
        ZStack {
            Circle()
                .stroke(POPColor.surfaceMuted, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((max(0, min(1, value)) * 100).rounded()))")
                .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
                .foregroundStyle(POPColor.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("\(Int((max(0, min(1, value)) * 100).rounded())) percent"))
    }
}

// MARK: - Rating dots (read-only display)

struct RatingDots: View {
    let rating: Int?
    let scaleMax: Int
    var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max(1, scaleMax), id: \.self) { index in
                Circle()
                    .fill(index <= (rating ?? 0) ? POPColor.brandOrange : POPColor.hairline)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rating.map { "Rating \($0) of \(scaleMax)" } ?? "Not rated"))
    }
}

// MARK: - Evidence coverage dots

struct EvidenceCoverageIndicator: View {
    let supporting: Int
    let contradicting: Int

    var body: some View {
        HStack(spacing: 5) {
            if supporting > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .bold))
                    Text("\(supporting)").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(POPColor.success)
            }
            if contradicting > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .bold))
                    Text("\(contradicting)").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(POPColor.danger)
            }
            if supporting == 0 && contradicting == 0 {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(POPColor.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(supporting) supporting, \(contradicting) contradicting"))
    }
}
