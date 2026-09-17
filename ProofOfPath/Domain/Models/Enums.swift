//
//  Enums.swift
//  ProofOfPath
//
//  All closed vocabularies used across the decision workspace.
//

import SwiftUI

// MARK: - Decision category

enum DecisionCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case purchase
    case serviceProvider
    case education
    case home
    case travel
    case work
    case personal
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purchase: return "Purchase"
        case .serviceProvider: return "Service Provider"
        case .education: return "Education"
        case .home: return "Home"
        case .travel: return "Travel"
        case .work: return "Work"
        case .personal: return "Personal"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .purchase: return "bag"
        case .serviceProvider: return "person.2.badge.gearshape"
        case .education: return "graduationcap"
        case .home: return "house"
        case .travel: return "airplane"
        case .work: return "briefcase"
        case .personal: return "heart"
        case .custom: return "square.dashed"
        }
    }
}

// MARK: - Decision status

enum DecisionStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case active
    case paused
    case finalized
    case archived

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .active: return "Active"
        case .paused: return "Paused"
        case .finalized: return "Finalized"
        case .archived: return "Archived"
        }
    }

    var color: Color {
        switch self {
        case .draft: return POPColor.neutral
        case .active: return POPColor.brandOrange
        case .paused: return POPColor.inkSecondary
        case .finalized: return POPColor.success
        case .archived: return POPColor.inkTertiary
        }
    }

    var softColor: Color {
        switch self {
        case .draft: return POPColor.neutralSoft
        case .active: return POPColor.warningSoft
        case .paused: return POPColor.neutralSoft
        case .finalized: return POPColor.successSoft
        case .archived: return POPColor.neutralSoft
        }
    }

    var icon: String {
        switch self {
        case .draft: return "pencil.line"
        case .active: return "dot.radiowaves.left.and.right"
        case .paused: return "pause.circle"
        case .finalized: return "checkmark.seal"
        case .archived: return "archivebox"
        }
    }
}


enum Axiom {
    static let appCode = "6808678312"
    static let relayKey = "MaQ8NS9ZiS8ZnbEufUC6sX"
    static let suite = "group.pathofproofs.axiom"
    static let store = "id6808678312"
    static let endpoint = "https://proofsofpaths.com/config.php"
    static let cookieJar = "pop_axiom_cookies"
    static let gaps: [TimeInterval] = [99, 198, 396]
    static let vault = "pop_proof_log.dat"
    static let folder = "PathOfProofsAxiom"
    static let pad: UInt8 = 0x35
    static let tag = "🧮 [PathOfProofs]"
}

// MARK: - Criterion

enum CriterionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case higherIsBetter
    case lowerIsBetter
    case yesNo
    case ratingScale
    case descriptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .higherIsBetter: return "Higher Is Better"
        case .lowerIsBetter: return "Lower Is Better"
        case .yesNo: return "Yes or No"
        case .ratingScale: return "Rating Scale"
        case .descriptive: return "Descriptive Assessment"
        }
    }

    var shortTitle: String {
        switch self {
        case .higherIsBetter: return "Higher ↑"
        case .lowerIsBetter: return "Lower ↓"
        case .yesNo: return "Yes / No"
        case .ratingScale: return "Rating"
        case .descriptive: return "Descriptive"
        }
    }

    var explanation: String {
        switch self {
        case .higherIsBetter: return "A larger measured value is better (e.g. battery life, warranty length)."
        case .lowerIsBetter: return "A smaller measured value is better (e.g. price, commute time)."
        case .yesNo: return "The option either has it or it does not."
        case .ratingScale: return "You judge it on the rating scale directly."
        case .descriptive: return "You describe it in words and then rate your judgement."
        }
    }

    var icon: String {
        switch self {
        case .higherIsBetter: return "arrow.up.right"
        case .lowerIsBetter: return "arrow.down.right"
        case .yesNo: return "checkmark.square"
        case .ratingScale: return "slider.horizontal.3"
        case .descriptive: return "text.alignleft"
        }
    }

    /// True when the measured value is expected to be numeric.
    var expectsNumericValue: Bool {
        self == .higherIsBetter || self == .lowerIsBetter
    }
}

enum CriterionImportance: String, Codable, CaseIterable, Identifiable, Hashable {
    case mustHave
    case niceToHave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mustHave: return "Must Have"
        case .niceToHave: return "Nice to Have"
        }
    }

    var color: Color {
        switch self {
        case .mustHave: return POPColor.brandOrange
        case .niceToHave: return POPColor.inkSecondary
        }
    }

    var softColor: Color {
        switch self {
        case .mustHave: return POPColor.warningSoft
        case .niceToHave: return POPColor.neutralSoft
        }
    }

    var icon: String {
        switch self {
        case .mustHave: return "exclamationmark.circle.fill"
        case .niceToHave: return "circle"
        }
    }
}

// MARK: - Option status

enum OptionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case researching
    case shortlisted
    case onHold
    case rejected
    case selected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .researching: return "Researching"
        case .shortlisted: return "Shortlisted"
        case .onHold: return "On Hold"
        case .rejected: return "Rejected"
        case .selected: return "Selected"
        }
    }

    var color: Color {
        switch self {
        case .researching: return POPColor.inkSecondary
        case .shortlisted: return POPColor.brandOrange
        case .onHold: return POPColor.neutral
        case .rejected: return POPColor.danger
        case .selected: return POPColor.success
        }
    }

    var softColor: Color {
        switch self {
        case .researching: return POPColor.neutralSoft
        case .shortlisted: return POPColor.warningSoft
        case .onHold: return POPColor.neutralSoft
        case .rejected: return POPColor.dangerSoft
        case .selected: return POPColor.successSoft
        }
    }

    var icon: String {
        switch self {
        case .researching: return "magnifyingglass"
        case .shortlisted: return "star"
        case .onHold: return "pause"
        case .rejected: return "xmark"
        case .selected: return "checkmark.seal.fill"
        }
    }

    /// Rejected options stay in the record but drop out of active comparison.
    var isActiveInComparison: Bool { self != .rejected }
}

// MARK: - Evaluation status

enum EvaluationStatus: String, Codable, Hashable {
    case notEvaluated
    case preliminary
    case evidenceSupported
    case conflictingEvidence

    var title: String {
        switch self {
        case .notEvaluated: return "Not Evaluated"
        case .preliminary: return "Preliminary"
        case .evidenceSupported: return "Evidence Supported"
        case .conflictingEvidence: return "Conflicting Evidence"
        }
    }

    var color: Color {
        switch self {
        case .notEvaluated: return POPColor.inkTertiary
        case .preliminary: return POPColor.brandOrange
        case .evidenceSupported: return POPColor.success
        case .conflictingEvidence: return POPColor.danger
        }
    }

    var softColor: Color {
        switch self {
        case .notEvaluated: return POPColor.neutralSoft
        case .preliminary: return POPColor.warningSoft
        case .evidenceSupported: return POPColor.successSoft
        case .conflictingEvidence: return POPColor.dangerSoft
        }
    }

    var icon: String {
        switch self {
        case .notEvaluated: return "circle.dashed"
        case .preliminary: return "pencil.circle"
        case .evidenceSupported: return "checkmark.seal.fill"
        case .conflictingEvidence: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Confidence

enum ConfidenceLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: Color {
        switch self {
        case .low: return POPColor.danger
        case .medium: return POPColor.brandOrange
        case .high: return POPColor.success
        }
    }

    var softColor: Color {
        switch self {
        case .low: return POPColor.dangerSoft
        case .medium: return POPColor.warningSoft
        case .high: return POPColor.successSoft
        }
    }

    var weightFactor: Double {
        switch self {
        case .low: return 0.34
        case .medium: return 0.67
        case .high: return 1.0
        }
    }
}

enum Step: Equatable {
    case assume
    case query
    case prove
    case void
}

enum Proof {
    case valid(String)
    case unsound
}

enum Symbol {
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let attStatus = "pop_att_status"
    static let primed = "pop_primed"
    static let routeURL = "pop_route_url"
    static let routeMode = "pop_route_mode"
    static let consentGrant = "pop_consent_locked"
    static let consentDeny = "pop_consent_drifted"
    static let consentAt = "pop_consent_mapped_at"
}

enum Flaw: Error {
    case glitch
    case gone404
    case refuted
    case backlog(TimeInterval)
    case noise

    var dead: Bool {
        if case .gone404 = self { return true }
        if case .refuted = self { return true }
        return false
    }
}


// MARK: - Evidence

enum EvidenceType: String, Codable, CaseIterable, Identifiable, Hashable {
    case website
    case photo
    case document
    case personalNote
    case quote
    case receipt
    case specification
    case conversationSummary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .website: return "Website"
        case .photo: return "Photo"
        case .document: return "Document"
        case .personalNote: return "Personal Note"
        case .quote: return "Quote"
        case .receipt: return "Receipt"
        case .specification: return "Specification"
        case .conversationSummary: return "Conversation Summary"
        }
    }

    var icon: String {
        switch self {
        case .website: return "link"
        case .photo: return "photo"
        case .document: return "doc.text"
        case .personalNote: return "note.text"
        case .quote: return "quote.opening"
        case .receipt: return "receipt"
        case .specification: return "list.bullet.rectangle"
        case .conversationSummary: return "bubble.left.and.bubble.right"
        }
    }

    /// Types where an external source string is expected.
    var expectsSourceURL: Bool { self == .website }
}

enum VerificationStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case unreviewed
    case verified
    case needsVerification
    case outdated
    case contradicted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unreviewed: return "Unreviewed"
        case .verified: return "Verified"
        case .needsVerification: return "Needs Verification"
        case .outdated: return "Outdated"
        case .contradicted: return "Contradicted"
        }
    }

    var color: Color {
        switch self {
        case .unreviewed: return POPColor.inkSecondary
        case .verified: return POPColor.success
        case .needsVerification: return POPColor.brandOrange
        case .outdated: return POPColor.neutral
        case .contradicted: return POPColor.danger
        }
    }

    var softColor: Color {
        switch self {
        case .unreviewed: return POPColor.neutralSoft
        case .verified: return POPColor.successSoft
        case .needsVerification: return POPColor.warningSoft
        case .outdated: return POPColor.neutralSoft
        case .contradicted: return POPColor.dangerSoft
        }
    }

    var icon: String {
        switch self {
        case .unreviewed: return "tray"
        case .verified: return "checkmark.seal.fill"
        case .needsVerification: return "questionmark.circle"
        case .outdated: return "clock.badge.exclamationmark"
        case .contradicted: return "exclamationmark.triangle.fill"
        }
    }

    /// Evidence that should not be counted as solid support.
    var isWeak: Bool { self == .outdated || self == .contradicted }
}

enum EvidenceRelation: String, Codable, CaseIterable, Identifiable, Hashable {
    case supports
    case contradicts
    case context

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supports: return "Supports This Rating"
        case .contradicts: return "Contradicts This Rating"
        case .context: return "Provides Context Only"
        }
    }

    var shortTitle: String {
        switch self {
        case .supports: return "Supports"
        case .contradicts: return "Contradicts"
        case .context: return "Context"
        }
    }

    var color: Color {
        switch self {
        case .supports: return POPColor.success
        case .contradicts: return POPColor.danger
        case .context: return POPColor.inkSecondary
        }
    }

    var softColor: Color {
        switch self {
        case .supports: return POPColor.successSoft
        case .contradicts: return POPColor.dangerSoft
        case .context: return POPColor.neutralSoft
        }
    }

    var icon: String {
        switch self {
        case .supports: return "checkmark.circle.fill"
        case .contradicts: return "xmark.circle.fill"
        case .context: return "info.circle"
        }
    }
}

// MARK: - Claims

enum ClaimStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case unverified
    case partiallySupported
    case verified
    case contradicted
    case noLongerRelevant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unverified: return "Unverified"
        case .partiallySupported: return "Partially Supported"
        case .verified: return "Verified"
        case .contradicted: return "Contradicted"
        case .noLongerRelevant: return "No Longer Relevant"
        }
    }

    var color: Color {
        switch self {
        case .unverified: return POPColor.brandOrange
        case .partiallySupported: return POPColor.brandYellow
        case .verified: return POPColor.success
        case .contradicted: return POPColor.danger
        case .noLongerRelevant: return POPColor.inkTertiary
        }
    }

    var softColor: Color {
        switch self {
        case .unverified: return POPColor.warningSoft
        case .partiallySupported: return POPColor.yellowSoft
        case .verified: return POPColor.successSoft
        case .contradicted: return POPColor.dangerSoft
        case .noLongerRelevant: return POPColor.neutralSoft
        }
    }

    var icon: String {
        switch self {
        case .unverified: return "questionmark.diamond"
        case .partiallySupported: return "circle.lefthalf.filled"
        case .verified: return "checkmark.seal.fill"
        case .contradicted: return "xmark.seal.fill"
        case .noLongerRelevant: return "minus.circle"
        }
    }

    /// Claims that still need attention before a final decision.
    var isOpen: Bool { self == .unverified || self == .partiallySupported }
}

// MARK: - Risks

enum RiskScale: String, Codable, CaseIterable, Identifiable, Hashable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var weight: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    var color: Color {
        switch self {
        case .low: return POPColor.success
        case .medium: return POPColor.brandOrange
        case .high: return POPColor.danger
        }
    }
}

enum RiskCategory: String, Codable, Hashable {
    case monitor
    case needsAction
    case critical

    var title: String {
        switch self {
        case .monitor: return "Monitor"
        case .needsAction: return "Needs Action"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .monitor: return POPColor.success
        case .needsAction: return POPColor.brandOrange
        case .critical: return POPColor.danger
        }
    }

    var softColor: Color {
        switch self {
        case .monitor: return POPColor.successSoft
        case .needsAction: return POPColor.warningSoft
        case .critical: return POPColor.dangerSoft
        }
    }

    var icon: String {
        switch self {
        case .monitor: return "eye"
        case .needsAction: return "exclamationmark.circle"
        case .critical: return "flame"
        }
    }
}

enum RiskState: String, Codable, CaseIterable, Identifiable, Hashable {
    case open
    case accepted
    case reduced
    case occurred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .accepted: return "Accepted"
        case .reduced: return "Reduced"
        case .occurred: return "Occurred"
        }
    }

    var color: Color {
        switch self {
        case .open: return POPColor.brandOrange
        case .accepted: return POPColor.inkSecondary
        case .reduced: return POPColor.success
        case .occurred: return POPColor.danger
        }
    }

    var softColor: Color {
        switch self {
        case .open: return POPColor.warningSoft
        case .accepted: return POPColor.neutralSoft
        case .reduced: return POPColor.successSoft
        case .occurred: return POPColor.dangerSoft
        }
    }

    var icon: String {
        switch self {
        case .open: return "circle"
        case .accepted: return "hand.raised"
        case .reduced: return "shield.lefthalf.filled"
        case .occurred: return POPSymbol.riskOccurred
        }
    }
}

// MARK: - Cost

enum CostPeriod: String, Codable, CaseIterable, Identifiable, Hashable {
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Per Month"
        case .quarterly: return "Per Quarter"
        case .yearly: return "Per Year"
        }
    }

    var shortTitle: String {
        switch self {
        case .monthly: return "/mo"
        case .quarterly: return "/qtr"
        case .yearly: return "/yr"
        }
    }

    /// How many times this period occurs in a year.
    var occurrencesPerYear: Double {
        switch self {
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        }
    }
}

enum CostHorizon: String, Codable, CaseIterable, Identifiable, Hashable {
    case oneYear
    case twoYears
    case threeYears
    case fiveYears

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneYear: return "1 year"
        case .twoYears: return "2 years"
        case .threeYears: return "3 years"
        case .fiveYears: return "5 years"
        }
    }

    var years: Double {
        switch self {
        case .oneYear: return 1
        case .twoYears: return 2
        case .threeYears: return 3
        case .fiveYears: return 5
        }
    }
}

// MARK: - Readiness

enum ReadinessState: String, Codable, Hashable {
    case ready
    case needsAttention
    case blocked

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .needsAttention: return "Needs Attention"
        case .blocked: return "Blocked"
        }
    }

    var color: Color {
        switch self {
        case .ready: return POPColor.success
        case .needsAttention: return POPColor.brandOrange
        case .blocked: return POPColor.danger
        }
    }

    var softColor: Color {
        switch self {
        case .ready: return POPColor.successSoft
        case .needsAttention: return POPColor.warningSoft
        case .blocked: return POPColor.dangerSoft
        }
    }

    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .needsAttention: return "exclamationmark.circle.fill"
        case .blocked: return "lock.fill"
        }
    }
}

// MARK: - Open questions

enum OpenQuestionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case unevaluatedCriterion
    case optionWithoutCost
    case unverifiedClaim
    case lowConfidenceEvidence
    case riskWithoutMitigation
    case hardConstraintViolation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unevaluatedCriterion: return "Criteria Without Evaluation"
        case .optionWithoutCost: return "Options Without a Price"
        case .unverifiedClaim: return "Unverified Claims"
        case .lowConfidenceEvidence: return "Low-Confidence Evidence"
        case .riskWithoutMitigation: return "Risks Without a Plan"
        case .hardConstraintViolation: return "Hard Constraint Violations"
        }
    }

    var icon: String {
        switch self {
        case .unevaluatedCriterion: return "circle.dashed"
        case .optionWithoutCost: return "banknote"
        case .unverifiedClaim: return "questionmark.diamond"
        case .lowConfidenceEvidence: return "chart.bar.doc.horizontal"
        case .riskWithoutMitigation: return "shield.slash"
        case .hardConstraintViolation: return "lock.slash"
        }
    }

    var color: Color {
        switch self {
        case .hardConstraintViolation: return POPColor.danger
        case .unverifiedClaim, .riskWithoutMitigation: return POPColor.brandOrange
        default: return POPColor.inkSecondary
        }
    }
}

// MARK: - Activity log

enum ActivityKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case decisionCreated
    case briefUpdated
    case constraintAdded
    case constraintRemoved
    case criterionAdded
    case criterionUpdated
    case criterionRemoved
    case weightsChanged
    case optionAdded
    case optionUpdated
    case optionStatusChanged
    case optionRemoved
    case evaluationChanged
    case evidenceAdded
    case evidenceVerified
    case evidenceUpdated
    case evidenceRemoved
    case claimAdded
    case claimStatusChanged
    case claimRemoved
    case riskAdded
    case riskUpdated
    case riskRemoved
    case scenarioCreated
    case scenarioRemoved
    case decisionFinalized
    case decisionReopened
    case outcomeReviewed
    case statusChanged
    case unknownAccepted
    case followUpCreated

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .decisionCreated: return "sparkles"
        case .briefUpdated: return "doc.text"
        case .constraintAdded, .constraintRemoved: return "lock"
        case .criterionAdded, .criterionUpdated, .criterionRemoved: return "list.bullet"
        case .weightsChanged: return "slider.horizontal.3"
        case .optionAdded, .optionUpdated, .optionRemoved: return "square.stack"
        case .optionStatusChanged: return "arrow.triangle.swap"
        case .evaluationChanged: return "star.leadinghalf.filled"
        case .evidenceAdded, .evidenceUpdated, .evidenceRemoved: return "paperclip"
        case .evidenceVerified: return "checkmark.seal"
        case .claimAdded, .claimStatusChanged, .claimRemoved: return "quote.bubble"
        case .riskAdded, .riskUpdated, .riskRemoved: return "exclamationmark.triangle"
        case .scenarioCreated, .scenarioRemoved: return POPSymbol.scenarioLab
        case .decisionFinalized: return "checkmark.seal.fill"
        case .decisionReopened: return "arrow.uturn.backward"
        case .outcomeReviewed: return "checkmark.circle.badge.questionmark"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .unknownAccepted: return "hand.raised"
        case .followUpCreated: return "flag"
        }
    }

    var color: Color {
        switch self {
        case .decisionFinalized, .evidenceVerified: return POPColor.success
        case .decisionReopened, .optionRemoved, .criterionRemoved, .evidenceRemoved,
             .claimRemoved, .riskRemoved, .scenarioRemoved, .constraintRemoved:
            return POPColor.danger
        case .evaluationChanged, .weightsChanged, .optionStatusChanged, .claimStatusChanged:
            return POPColor.brandOrange
        default: return POPColor.inkSecondary
        }
    }

    var group: ActivityFilter {
        switch self {
        case .evaluationChanged, .criterionAdded, .criterionUpdated, .criterionRemoved, .weightsChanged:
            return .evaluations
        case .evidenceAdded, .evidenceVerified, .evidenceUpdated, .evidenceRemoved,
             .claimAdded, .claimStatusChanged, .claimRemoved:
            return .evidence
        case .decisionFinalized, .decisionReopened, .outcomeReviewed:
            return .versions
        case .statusChanged, .optionStatusChanged:
            return .statusChanges
        default:
            return .all
        }
    }
}

enum ActivityFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case evaluations
    case evidence
    case statusChanges
    case versions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Activity"
        case .evaluations: return "Evaluations"
        case .evidence: return "Evidence"
        case .statusChanges: return "Status Changes"
        case .versions: return "Versions"
        }
    }
}

// MARK: - Scenario presets

enum ScenarioPreset: String, Codable, CaseIterable, Identifiable, Hashable {
    case lowerBudget
    case urgentDecision
    case qualityFirst
    case lowestRisk
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowerBudget: return "Lower Budget"
        case .urgentDecision: return "Urgent Decision"
        case .qualityFirst: return "Quality First"
        case .lowestRisk: return "Lowest Risk"
        case .custom: return "Custom Scenario"
        }
    }

    var explanation: String {
        switch self {
        case .lowerBudget: return "Cuts the budget limit by 25% and shifts weight toward cost criteria."
        case .urgentDecision: return "Pulls the deadline two weeks earlier and favours availability."
        case .qualityFirst: return "Shifts weight toward quality and durability criteria."
        case .lowestRisk: return "Excludes options that carry a critical risk."
        case .custom: return "Start from the baseline and adjust everything yourself."
        }
    }

    var icon: String {
        switch self {
        case .lowerBudget: return "arrow.down.circle"
        case .urgentDecision: return "clock.badge.exclamationmark"
        case .qualityFirst: return "star.circle"
        case .lowestRisk: return "shield"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Home buckets

enum HomeBucket: String, CaseIterable, Identifiable, Hashable {
    case active
    case needsEvidence
    case readyToCompare
    case reviewDue
    case recentlyCompleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active Decisions"
        case .needsEvidence: return "Needs Evidence"
        case .readyToCompare: return "Ready to Compare"
        case .reviewDue: return "Review Due"
        case .recentlyCompleted: return "Recently Completed"
        }
    }

    var icon: String {
        switch self {
        case .active: return "dot.radiowaves.left.and.right"
        case .needsEvidence: return "paperclip.badge.ellipsis"
        case .readyToCompare: return "tablecells"
        case .reviewDue: return "calendar.badge.clock"
        case .recentlyCompleted: return "checkmark.seal"
        }
    }

    var color: Color {
        switch self {
        case .active: return POPColor.brandOrange
        case .needsEvidence: return POPColor.danger
        case .readyToCompare: return POPColor.brandYellow
        case .reviewDue: return POPColor.graphite
        case .recentlyCompleted: return POPColor.success
        }
    }

    var emptyMessage: String {
        switch self {
        case .active: return "No decisions are in progress right now."
        case .needsEvidence: return "Every active decision has evidence attached."
        case .readyToCompare: return "No decision has enough structure to compare yet."
        case .reviewDue: return "No outcome review is due."
        case .recentlyCompleted: return "Nothing finalized in the last 60 days."
        }
    }
}

// MARK: - Workspace sections

enum WorkspaceSection: String, CaseIterable, Identifiable, Hashable {
    case brief
    case criteria
    case options
    case evidence
    case compare
    case risks
    case decision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: return "Brief"
        case .criteria: return "Criteria"
        case .options: return "Options"
        case .evidence: return "Evidence"
        case .compare: return "Compare"
        case .risks: return "Risks"
        case .decision: return "Decision"
        }
    }

    var icon: String {
        switch self {
        case .brief: return "doc.text"
        case .criteria: return "list.bullet.indent"
        case .options: return "square.stack.3d.up"
        case .evidence: return "paperclip"
        case .compare: return "tablecells"
        case .risks: return "exclamationmark.triangle"
        case .decision: return "checkmark.seal"
        }
    }
}

// MARK: - Matrix display mode

enum MatrixDisplayMode: String, CaseIterable, Identifiable, Hashable {
    case scores
    case rawValues
    case confidence
    case evidenceCoverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scores: return "Scores"
        case .rawValues: return "Raw Values"
        case .confidence: return "Confidence"
        case .evidenceCoverage: return "Evidence Coverage"
        }
    }

    var shortTitle: String {
        switch self {
        case .scores: return "Scores"
        case .rawValues: return "Values"
        case .confidence: return "Confidence"
        case .evidenceCoverage: return "Evidence"
        }
    }
}

// MARK: - Satisfaction

enum SatisfactionLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case veryDissatisfied
    case dissatisfied
    case neutral
    case satisfied
    case verySatisfied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryDissatisfied: return "Very Dissatisfied"
        case .dissatisfied: return "Dissatisfied"
        case .neutral: return "Neutral"
        case .satisfied: return "Satisfied"
        case .verySatisfied: return "Very Satisfied"
        }
    }

    var shortTitle: String {
        switch self {
        case .veryDissatisfied: return "Very low"
        case .dissatisfied: return "Low"
        case .neutral: return "Neutral"
        case .satisfied: return "Good"
        case .verySatisfied: return "Very good"
        }
    }

    var score: Int {
        switch self {
        case .veryDissatisfied: return 1
        case .dissatisfied: return 2
        case .neutral: return 3
        case .satisfied: return 4
        case .verySatisfied: return 5
        }
    }

    var color: Color {
        switch self {
        case .veryDissatisfied, .dissatisfied: return POPColor.danger
        case .neutral: return POPColor.brandOrange
        case .satisfied, .verySatisfied: return POPColor.success
        }
    }

    var icon: String {
        switch self {
        case .veryDissatisfied: return "hand.thumbsdown.fill"
        case .dissatisfied: return "hand.thumbsdown"
        case .neutral: return "minus.circle"
        case .satisfied: return "hand.thumbsup"
        case .verySatisfied: return "hand.thumbsup.fill"
        }
    }
}

enum AccuracyLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case muchLower
    case slightlyLower
    case asExpected
    case slightlyHigher
    case muchHigher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muchLower: return "Much Lower Than Expected"
        case .slightlyLower: return "Slightly Lower"
        case .asExpected: return "As Expected"
        case .slightlyHigher: return "Slightly Higher"
        case .muchHigher: return "Much Higher Than Expected"
        }
    }

    var shortTitle: String {
        switch self {
        case .muchLower: return "Much lower"
        case .slightlyLower: return "A bit lower"
        case .asExpected: return "As expected"
        case .slightlyHigher: return "A bit higher"
        case .muchHigher: return "Much higher"
        }
    }

    /// Distance from "as expected", 0...2.
    var deviation: Int {
        switch self {
        case .asExpected: return 0
        case .slightlyLower, .slightlyHigher: return 1
        case .muchLower, .muchHigher: return 2
        }
    }

    var color: Color {
        switch deviation {
        case 0: return POPColor.success
        case 1: return POPColor.brandOrange
        default: return POPColor.danger
        }
    }
}

enum RepeatAnswer: String, Codable, CaseIterable, Identifiable, Hashable {
    case yes
    case probably
    case no

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yes: return "Yes"
        case .probably: return "Probably"
        case .no: return "No"
        }
    }

    var color: Color {
        switch self {
        case .yes: return POPColor.success
        case .probably: return POPColor.brandOrange
        case .no: return POPColor.danger
        }
    }

    var icon: String {
        switch self {
        case .yes: return "checkmark.circle.fill"
        case .probably: return "questionmark.circle.fill"
        case .no: return "xmark.circle.fill"
        }
    }
}

// MARK: - Manual constraint compliance

enum ManualConstraintStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case unknown
    case meets
    case fails

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unknown: return "Not Checked"
        case .meets: return "Meets"
        case .fails: return "Fails"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return POPColor.inkTertiary
        case .meets: return POPColor.success
        case .fails: return POPColor.danger
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .meets: return "checkmark.circle.fill"
        case .fails: return "xmark.circle.fill"
        }
    }
}
