//
//  OnboardingView.swift
//  ProofOfPath
//
//  Four screens that explain the process, then hand over to the first decision.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var page = 0
    @State private var showCreateSheet = false

    private let pages = OnboardingPage.all

    var body: some View {
        ZStack {
            POPColor.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button(action: {
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.25)) { page = pages.count - 1 }
                        }) {
                            Text("Skip")
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.inkSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                        }
                        .accessibilityIdentifier("onboarding.skip")
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                            // A paged TabView keeps every page in the hierarchy.
                            // Without this, VoiceOver reads all four screens at
                            // once and lands on controls that are off-screen.
                            .accessibilityHidden(index != page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Dots
                HStack(spacing: 7) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? POPColor.brandOrange : POPColor.hairline)
                            .frame(width: index == page ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                    }
                }
                .padding(.bottom, 20)

                VStack(spacing: 10) {
                    POPPrimaryButton(
                        title: page == pages.count - 1 ? "Create Your First Decision" : "Continue",
                        icon: page == pages.count - 1 ? "plus" : nil
                    ) {
                        if page == pages.count - 1 {
                            showCreateSheet = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
                        }
                    }
                    .accessibilityIdentifier(page == pages.count - 1 ? "onboarding.create" : "onboarding.continue")

                    if page == pages.count - 1 {
                        POPTextButton(title: "Explore the app first", tint: POPColor.inkSecondary) {
                            store.send(.completeOnboarding)
                        }
                        .accessibilityIdentifier("onboarding.explore")
                    }
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateDecisionFlow(onFinished: {
                store.send(.completeOnboarding)
            })
        }
    }
}

// MARK: - Page model

struct OnboardingPage: Identifiable, Hashable {
    let id: Int
    let title: String
    let body: String
    let icon: String
    let bullets: [String]

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Make Decisions with Evidence",
            body: "ProofPath turns a difficult choice into a process you can retrace. Nothing is decided for you — the app keeps your reasoning organised.",
            icon: "doc.text.magnifyingglass",
            bullets: [
                "Works fully offline, with no account",
                "Every number comes from something you entered",
                "Your reasoning is saved, not just the answer"
            ]
        ),
        OnboardingPage(
            id: 1,
            title: "Define What Matters",
            body: "Before you look at options, you decide what actually counts. Criteria carry weights, and Must-Have criteria act as hard requirements.",
            icon: "list.bullet.indent",
            bullets: [
                "Weights must add up to exactly 100%",
                "Must-Have criteria disqualify options that fail them",
                "Reorder and rebalance whenever your priorities move"
            ]
        ),
        OnboardingPage(
            id: 2,
            title: "Separate Facts from Assumptions",
            body: "Opinions, verified facts, sources, assumptions and risks are stored separately — so you always know which is which.",
            icon: "square.stack.3d.up",
            bullets: [
                "Attach links, photos, documents and notes",
                "Mark each item as supporting, contradicting or context",
                "Unverified claims stay visible until you resolve them"
            ]
        ),
        OnboardingPage(
            id: 3,
            title: "Create Your First Decision",
            body: "Start with the choice in front of you. You can add criteria, options and evidence as you go — and later compare what you expected with what actually happened.",
            icon: "flag.checkered",
            bullets: [
                "Start from scratch or from a starting structure",
                "Compare scenarios before you commit",
                "Come back after the fact and review the outcome"
            ]
        )
    ]
}

// MARK: - Page view

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingArtwork(index: page.id, icon: page.icon)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text(page.title)
                        .font(POPFont.display(29))
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.body)
                        .font(POPFont.body)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(page.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(POPColor.success)
                                .padding(.top, 1)
                            Text(bullet)
                                .font(POPFont.callout)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(POPColor.surfaceSunk))

                Spacer(minLength: 8)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 4)
        }
    }
}

// MARK: - Artwork

/// Simple built-from-shapes illustrations — no placeholder images, no fake data.
struct OnboardingArtwork: View {
    let index: Int
    let icon: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(POPColor.surfaceSunk)

            switch index {
            case 0: boardArtwork
            case 1: weightsArtwork
            case 2: evidenceArtwork
            default: pathArtwork
            }
        }
    }

    // Pinned cards connected with a thread.
    private var boardArtwork: some View {
        ZStack {
            pinnedCard(width: 88, height: 58, rotation: -7, color: POPColor.surface)
                .offset(x: -62, y: -28)
            pinnedCard(width: 78, height: 50, rotation: 5, color: POPColor.brandYellow)
                .offset(x: 58, y: -34)
            pinnedCard(width: 96, height: 54, rotation: -3, color: POPColor.surface)
                .offset(x: 8, y: 40)

            Path { path in
                path.move(to: CGPoint(x: 55, y: 62))
                path.addLine(to: CGPoint(x: 175, y: 56))
                path.addLine(to: CGPoint(x: 125, y: 130))
                path.addLine(to: CGPoint(x: 55, y: 62))
            }
            .stroke(POPColor.brandOrange.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
            .frame(width: 240, height: 180)
            .offset(x: -6, y: -4)

            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(POPColor.graphite)
                .offset(x: 8, y: 40)
        }
    }

    // Weight bars adding up to a full ring.
    private var weightsArtwork: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                weightRow(width: 108, tint: POPColor.brandOrange, label: "35%")
                weightRow(width: 82, tint: POPColor.brandYellow, label: "25%")
                weightRow(width: 66, tint: POPColor.graphite.opacity(0.55), label: "20%")
                weightRow(width: 52, tint: POPColor.hairline, label: "20%")
            }
            ZStack {
                Circle()
                    .stroke(POPColor.surface, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(POPColor.brandOrange, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("100")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(POPColor.ink)
                    Text("%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
            .frame(width: 74, height: 74)
        }
        .padding(.horizontal, 22)
    }

    // Fact vs assumption cards.
    private var evidenceArtwork: some View {
        VStack(spacing: 11) {
            factRow(icon: "checkmark.seal.fill", tint: POPColor.success, title: "Verified fact", width: 176)
            factRow(icon: "exclamationmark.triangle.fill", tint: POPColor.danger, title: "Contradicted", width: 150)
            factRow(icon: "questionmark.diamond.fill", tint: POPColor.brandOrange, title: "Unverified claim", width: 192)
            factRow(icon: "info.circle.fill", tint: POPColor.inkSecondary, title: "Context only", width: 132)
        }
    }

    // A path from question to reviewed outcome.
    private var pathArtwork: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                milestone(icon: "questionmark", tint: POPColor.graphite, filled: false)
                connector
                milestone(icon: "list.bullet", tint: POPColor.graphite, filled: false)
                connector
                milestone(icon: "tablecells", tint: POPColor.brandOrange, filled: true)
                connector
                milestone(icon: "checkmark", tint: POPColor.success, filled: true)
            }
            Text("Question → Criteria → Compare → Outcome")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(POPColor.inkSecondary)
                .padding(.top, 16)
        }
    }

    // MARK: pieces

    private var connector: some View {
        Rectangle()
            .fill(POPColor.brandOrange.opacity(0.45))
            .frame(width: 22, height: 2)
    }

    private func milestone(icon: String, tint: Color, filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? tint : POPColor.surface)
            Circle()
                .strokeBorder(tint.opacity(0.55), lineWidth: 1.6)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? POPColor.onDark : tint)
        }
        .frame(width: 42, height: 42)
    }

    private func pinnedCard(width: CGFloat, height: CGFloat, rotation: Double, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(POPColor.graphite.opacity(0.12), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Circle()
                    .fill(POPColor.brandOrange)
                    .frame(width: 8, height: 8)
                    .offset(y: -3)
            }
            .rotationEffect(.degrees(rotation))
    }

    private func weightRow(width: CGFloat, tint: Color, label: String) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(tint)
                .frame(width: width, height: 11)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(POPColor.inkSecondary)
        }
    }

    private func factRow(icon: String, tint: Color, title: String, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(POPColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 32, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(POPColor.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
    }
}
