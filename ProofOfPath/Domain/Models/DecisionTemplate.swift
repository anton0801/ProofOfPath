//
//  DecisionTemplate.swift
//  ProofOfPath
//
//  Templates are starting structures, not filled-in decisions.
//  They create suggested criteria only — never options, evidence or ratings.
//

import Foundation

struct TemplateCriterion: Hashable {
    let name: String
    let details: String
    let kind: CriterionKind
    let importance: CriterionImportance
    let measurementMethod: String
    let suggestedWeight: Double
}

struct DecisionTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let category: DecisionCategory
    let criteria: [TemplateCriterion]

    var suggestedWeightTotal: Double { criteria.reduce(0) { $0 + $1.suggestedWeight } }
}

enum DecisionTemplateLibrary {

    static let all: [DecisionTemplate] = [
        compareProduct,
        chooseServiceProvider,
        evaluateCourse,
        planMove,
        blank
    ]

    static func template(id: String?) -> DecisionTemplate? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    // MARK: Compare a Product

    static let compareProduct = DecisionTemplate(
        id: "product",
        title: "Compare a Product",
        subtitle: "Appliances, electronics, furniture, tools",
        icon: "bag",
        category: .purchase,
        criteria: [
            TemplateCriterion(name: "Total price", details: "Everything you pay to own it, not just the sticker price.",
                              kind: .lowerIsBetter, importance: .mustHave,
                              measurementMethod: "Add price, delivery and required accessories.", suggestedWeight: 25),
            TemplateCriterion(name: "Build quality", details: "Materials, finish and how well it is put together.",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Inspect in person or read teardown reviews.", suggestedWeight: 20),
            TemplateCriterion(name: "Warranty length", details: "Months of manufacturer cover.",
                              kind: .higherIsBetter, importance: .niceToHave,
                              measurementMethod: "Read the warranty document, not the ad.", suggestedWeight: 15),
            TemplateCriterion(name: "Repairability", details: "Can it be fixed locally and are parts available?",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Check for a local service centre and spare-part listings.", suggestedWeight: 15),
            TemplateCriterion(name: "Fits my space", details: "Physical dimensions against the space you have.",
                              kind: .yesNo, importance: .mustHave,
                              measurementMethod: "Measure the space and compare with the spec sheet.", suggestedWeight: 15),
            TemplateCriterion(name: "Running cost", details: "Energy, consumables or subscription fees.",
                              kind: .lowerIsBetter, importance: .niceToHave,
                              measurementMethod: "Use the label rating or an owner's actual bills.", suggestedWeight: 10)
        ]
    )

    // MARK: Choose a Service Provider

    static let chooseServiceProvider = DecisionTemplate(
        id: "provider",
        title: "Choose a Service Provider",
        subtitle: "Contractors, agencies, clinics, repair shops",
        icon: "person.2.badge.gearshape",
        category: .serviceProvider,
        criteria: [
            TemplateCriterion(name: "Quoted price", details: "The written quote, not a verbal estimate.",
                              kind: .lowerIsBetter, importance: .mustHave,
                              measurementMethod: "Request a written, itemised quote.", suggestedWeight: 25),
            TemplateCriterion(name: "Verifiable references", details: "Past clients you can actually contact.",
                              kind: .ratingScale, importance: .mustHave,
                              measurementMethod: "Call at least two references and note the date.", suggestedWeight: 20),
            TemplateCriterion(name: "Written guarantee", details: "A guarantee you can hold them to.",
                              kind: .yesNo, importance: .mustHave,
                              measurementMethod: "Ask for the guarantee terms in writing.", suggestedWeight: 15),
            TemplateCriterion(name: "Start date", details: "How soon they can actually begin.",
                              kind: .lowerIsBetter, importance: .niceToHave,
                              measurementMethod: "Days from today until they can start.", suggestedWeight: 15),
            TemplateCriterion(name: "Communication", details: "Response time and clarity during the quote stage.",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Track how long each reply took.", suggestedWeight: 15),
            TemplateCriterion(name: "Insurance and licence", details: "Documents that protect you if something goes wrong.",
                              kind: .yesNo, importance: .niceToHave,
                              measurementMethod: "Ask for the certificate number and check it.", suggestedWeight: 10)
        ]
    )

    // MARK: Evaluate a Course

    static let evaluateCourse = DecisionTemplate(
        id: "course",
        title: "Evaluate a Course",
        subtitle: "Training, degrees, certifications, bootcamps",
        icon: "graduationcap",
        category: .education,
        criteria: [
            TemplateCriterion(name: "Total cost", details: "Tuition plus materials, exams and travel.",
                              kind: .lowerIsBetter, importance: .mustHave,
                              measurementMethod: "Add every fee listed in the enrolment terms.", suggestedWeight: 20),
            TemplateCriterion(name: "Time commitment per week", details: "Realistic hours, including homework.",
                              kind: .lowerIsBetter, importance: .mustHave,
                              measurementMethod: "Ask current students, not the brochure.", suggestedWeight: 20),
            TemplateCriterion(name: "Curriculum relevance", details: "How closely it matches what you need to do.",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Compare the syllabus against your own goal list.", suggestedWeight: 20),
            TemplateCriterion(name: "Recognised credential", details: "Does anyone who matters recognise it?",
                              kind: .yesNo, importance: .niceToHave,
                              measurementMethod: "Search job listings for the credential name.", suggestedWeight: 15),
            TemplateCriterion(name: "Instructor experience", details: "Practical background of the people teaching.",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Read instructor profiles and past work.", suggestedWeight: 15),
            TemplateCriterion(name: "Refund policy", details: "What happens if you have to stop.",
                              kind: .descriptive, importance: .niceToHave,
                              measurementMethod: "Read the cancellation clause in full.", suggestedWeight: 10)
        ]
    )

    // MARK: Plan a Move

    static let planMove = DecisionTemplate(
        id: "move",
        title: "Plan a Move",
        subtitle: "Neighbourhoods, cities, apartments",
        icon: "house",
        category: .home,
        criteria: [
            TemplateCriterion(name: "Monthly housing cost", details: "Rent or mortgage plus utilities.",
                              kind: .lowerIsBetter, importance: .mustHave,
                              measurementMethod: "Use actual listings and a recent utility bill.", suggestedWeight: 25),
            TemplateCriterion(name: "Commute time", details: "Door to door on a normal weekday.",
                              kind: .lowerIsBetter, importance: .mustHave,
                              measurementMethod: "Test the route at the hour you would travel.", suggestedWeight: 20),
            TemplateCriterion(name: "Space", details: "Rooms and square meters against what you need.",
                              kind: .higherIsBetter, importance: .niceToHave,
                              measurementMethod: "Compare floor plans, not photos.", suggestedWeight: 15),
            TemplateCriterion(name: "Neighbourhood safety", details: "How safe it feels and what the records say.",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Visit in the evening and check public records.", suggestedWeight: 15),
            TemplateCriterion(name: "Daily amenities nearby", details: "Shops, schools, healthcare within walking distance.",
                              kind: .ratingScale, importance: .niceToHave,
                              measurementMethod: "Walk the area and list what is within 15 minutes.", suggestedWeight: 15),
            TemplateCriterion(name: "Moving cost", details: "One-off cost of getting your things there.",
                              kind: .lowerIsBetter, importance: .niceToHave,
                              measurementMethod: "Collect two removal quotes.", suggestedWeight: 10)
        ]
    )

    // MARK: Blank

    static let blank = DecisionTemplate(
        id: "blank",
        title: "Custom Decision",
        subtitle: "Start from scratch and define everything yourself",
        icon: "square.dashed",
        category: .custom,
        criteria: []
    )
}
