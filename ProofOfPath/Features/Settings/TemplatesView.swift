//
//  TemplatesView.swift
//  ProofOfPath
//
//  Starting structures — never fake decisions, options, data or ratings.
//

import SwiftUI

struct TemplatesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedTemplateID: String?
    @State private var showCreate = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                CoinStrikeFeatureBanner(asset: "CoinStrikeTemplates")
                POPBanner(
                    kind: .neutral,
                    message: "A structure is a starting point, not a filled-in decision.",
                    detail: "Each one adds suggested criteria that you must review. It never creates options, evidence or ratings for you."
                )

                ForEach(DecisionTemplateLibrary.all) { template in
                    templateCard(template)
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Starting Structures")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate) {
            CreateDecisionFlow(preselectedTemplateID: selectedTemplateID)
        }
    }

    private func templateCard(_ template: DecisionTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: template.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.warningSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(POPFont.cardTitle)
                        .foregroundStyle(POPColor.ink)
                    Text(template.subtitle)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if template.criteria.isEmpty {
                POPInlineNote(text: "No suggested criteria — you define everything yourself.")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Suggested Criteria")
                            .font(POPFont.micro)
                            .foregroundStyle(POPColor.inkTertiary)
                        Spacer()
                        Text("Total \(POPFormat.percent(template.suggestedWeightTotal))")
                            .font(POPFont.micro)
                            .foregroundStyle(abs(template.suggestedWeightTotal - 100) < 0.01 ? POPColor.success : POPColor.brandOrange)
                    }
                    ForEach(Array(template.criteria.enumerated()), id: \.offset) { _, criterion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: criterion.kind.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(POPColor.inkSecondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(criterion.name)
                                        .font(POPFont.callout)
                                        .foregroundStyle(POPColor.ink)
                                    POPBadge(text: criterion.importance.title,
                                             color: criterion.importance.color,
                                             soft: criterion.importance.softColor, compact: true)
                                }
                                Text(criterion.details)
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Text(POPFormat.percent(criterion.suggestedWeight))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(POPColor.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.surfaceMuted))
            }

            POPPrimaryButton(
                title: template.criteria.isEmpty ? "Start from Scratch" : "Use This Structure",
                icon: "plus"
            ) {
                selectedTemplateID = template.id == "blank" ? nil : template.id
                showCreate = true
            }
        }
        .popCard()
    }
}
