//
//  AppIntent.swift
//  ProofOfPath
//
//  MVI — every state change in the app enters through exactly one of these.
//

import Foundation

/// Payload used when creating a decision from the wizard.
struct DecisionDraft: Equatable {
    var title: String = ""
    var category: DecisionCategory = .purchase
    var customCategoryName: String = ""
    var desiredOutcome: String = ""
    var whyItMatters: String = ""
    var peopleAffected: String = ""
    var budgetMin: Double?
    var budgetMax: Double?
    var currencyCode: String = "USD"
    var deadline: Date?
    var preferredCompletionDate: Date?
    var hardConstraints: [HardConstraint] = []
    var owner: String = ""
    var templateID: String?
    var templateCriteria: [TemplateCriterion] = []
    var saveAsDraft: Bool = false
}

enum AppIntent: Equatable {

    // MARK: Lifecycle
    case load
    case dismissToast
    case dismissConstraintNotice

    // MARK: Onboarding & settings
    case completeOnboarding
    case resetOnboarding
    case setDefaultCurrency(String)
    case setRatingScale(Int)
    case setRemindersEnabled(Bool)
    case setReminderLeadDays(Int)
    case setHapticsEnabled(Bool)
    case setOwnerName(String)
    case replaceAllData(AppData)
    case deleteAllData

    // MARK: Decisions
    case createDecision(DecisionDraft)
    case updateDecisionBrief(decisionID: UUID, brief: DecisionBriefEdit)
    case setDecisionStatus(decisionID: UUID, status: DecisionStatus)
    case archiveDecision(UUID)
    case restoreDecision(UUID)
    case deleteDecision(UUID)
    case setCostHorizon(decisionID: UUID, horizon: CostHorizon)

    // MARK: Hard constraints
    case addConstraint(decisionID: UUID, constraint: HardConstraint)
    case updateConstraint(decisionID: UUID, constraint: HardConstraint)
    case deleteConstraint(decisionID: UUID, constraintID: UUID)
    case setManualConstraintStatus(decisionID: UUID, optionID: UUID, constraintID: UUID, status: ManualConstraintStatus)

    // MARK: Criteria
    case addCriterion(decisionID: UUID, criterion: Criterion)
    case updateCriterion(decisionID: UUID, criterion: Criterion)
    case deleteCriterion(decisionID: UUID, criterionID: UUID)
    case duplicateCriterion(decisionID: UUID, criterionID: UUID)
    case moveCriteria(decisionID: UUID, from: IndexSet, to: Int)
    case setCriterionWeight(decisionID: UUID, criterionID: UUID, weight: Double)
    case balanceCriteriaWeights(decisionID: UUID)
    case applyTemplateCriteria(decisionID: UUID, templateID: String, criteria: [TemplateCriterion])

    // MARK: Options
    case addOption(decisionID: UUID, option: DecisionOption)
    case updateOption(decisionID: UUID, option: DecisionOption)
    case setOptionStatus(decisionID: UUID, optionID: UUID, status: OptionStatus)
    case duplicateOption(decisionID: UUID, optionID: UUID)
    case deleteOption(decisionID: UUID, optionID: UUID)
    case moveOptions(decisionID: UUID, from: IndexSet, to: Int)
    case setOptionImage(decisionID: UUID, optionID: UUID, fileName: String?)

    // MARK: Evaluations
    case saveEvaluation(decisionID: UUID, optionID: UUID, evaluation: Evaluation)
    case clearEvaluation(decisionID: UUID, optionID: UUID, criterionID: UUID)

    // MARK: Evidence
    case addEvidence(Evidence)
    case updateEvidence(Evidence)
    case deleteEvidence(UUID)
    case setEvidenceVerification(evidenceID: UUID, status: VerificationStatus)
    case addEvidenceLink(evidenceID: UUID, link: EvidenceLink)
    case updateEvidenceLink(evidenceID: UUID, link: EvidenceLink)
    case removeEvidenceLink(evidenceID: UUID, linkID: UUID)

    // MARK: Claims
    case addClaim(decisionID: UUID, claim: Claim)
    case updateClaim(decisionID: UUID, claim: Claim)
    case deleteClaim(decisionID: UUID, claimID: UUID)
    case setClaimStatus(decisionID: UUID, claimID: UUID, status: ClaimStatus)
    case linkClaimEvidence(decisionID: UUID, claimID: UUID, evidenceID: UUID, supporting: Bool)
    case unlinkClaimEvidence(decisionID: UUID, claimID: UUID, evidenceID: UUID)
    case requestClaimVerification(decisionID: UUID, claimID: UUID, deadline: Date?)

    // MARK: Risks
    case addRisk(decisionID: UUID, risk: Risk)
    case updateRisk(decisionID: UUID, risk: Risk)
    case deleteRisk(decisionID: UUID, riskID: UUID)
    case setRiskState(decisionID: UUID, riskID: UUID, state: RiskState, reason: String)

    // MARK: Scenarios
    case addScenario(decisionID: UUID, scenario: Scenario)
    case updateScenario(decisionID: UUID, scenario: Scenario)
    case duplicateScenario(decisionID: UUID, scenarioID: UUID)
    case deleteScenario(decisionID: UUID, scenarioID: UUID)

    // MARK: Open questions
    case acceptUnknown(decisionID: UUID, question: AcceptedUnknownDraft)
    case removeAcceptedUnknown(decisionID: UUID, unknownID: UUID)
    case addFollowUp(decisionID: UUID, task: FollowUpTask)
    case toggleFollowUp(decisionID: UUID, taskID: UUID)
    case deleteFollowUp(decisionID: UUID, taskID: UUID)

    // MARK: Finalize
    case saveFinalDecisionDraft(decisionID: UUID, decisionRecord: FinalDecision)
    case finalizeDecision(decisionID: UUID, decisionRecord: FinalDecision)
    case reopenDecision(decisionID: UUID, reason: String)

    // MARK: Outcome review
    case saveOutcomeReviewDraft(decisionID: UUID, review: OutcomeReview)
    case completeOutcomeReview(decisionID: UUID, review: OutcomeReview)
    case markPurchaseCompleted(decisionID: UUID)
}

/// Editable slice of the brief screen.
struct DecisionBriefEdit: Equatable {
    var title: String
    var category: DecisionCategory
    var customCategoryName: String
    var desiredOutcome: String
    var whyItMatters: String
    var peopleAffected: String
    var budgetMin: Double?
    var budgetMax: Double?
    var currencyCode: String
    var deadline: Date?
    var preferredCompletionDate: Date?
    var owner: String

    init(decision: Decision) {
        title = decision.title
        category = decision.category
        customCategoryName = decision.customCategoryName
        desiredOutcome = decision.desiredOutcome
        whyItMatters = decision.whyItMatters
        peopleAffected = decision.peopleAffected
        budgetMin = decision.budgetMin
        budgetMax = decision.budgetMax
        currencyCode = decision.currencyCode
        deadline = decision.deadline
        preferredCompletionDate = decision.preferredCompletionDate
        owner = decision.owner
    }
}

struct AcceptedUnknownDraft: Equatable {
    let questionKey: String
    let kind: OpenQuestionKind
    let label: String
    let reason: String
}
