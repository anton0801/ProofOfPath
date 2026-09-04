//
//  TestSupport.swift
//  ProofOfPathTests
//

import XCTest
@testable import ProofOfPath

/// Runs one intent through the real reducer.
@MainActor
func reduce(_ state: AppState, _ intent: AppIntent) -> AppState {
    AppReducer.reduce(state: state, intent: intent).state
}

@MainActor
func effects(_ state: AppState, _ intent: AppIntent) -> [AppEffect] {
    AppReducer.reduce(state: state, intent: intent).effects
}

func makeCriterion(_ name: String,
                   kind: CriterionKind = .ratingScale,
                   importance: CriterionImportance = .niceToHave,
                   weight: Double = 0,
                   minimum: String = "",
                   sortIndex: Int = 0) -> Criterion {
    var c = Criterion()
    c.name = name
    c.kind = kind
    c.importance = importance
    c.weight = weight
    c.minimumAcceptableValue = minimum
    c.sortIndex = sortIndex
    return c
}

func makeOption(_ name: String, cost: Double? = nil, sortIndex: Int = 0) -> DecisionOption {
    var o = DecisionOption()
    o.name = name
    o.estimatedCost = cost
    o.sortIndex = sortIndex
    return o
}

func makeEvaluation(_ criterionID: UUID,
                    rating: Int? = nil,
                    value: String = "",
                    bool: Bool? = nil,
                    reason: String = "",
                    confidence: ConfidenceLevel = .medium) -> Evaluation {
    var e = Evaluation(criterionID: criterionID)
    e.rating = rating
    e.measuredValue = value
    e.numericValue = POPFormat.parseNumber(value)
    e.boolValue = bool
    e.reason = reason
    e.confidence = confidence
    return e
}

func makeDraft(_ title: String, outcome: String = "An outcome") -> DecisionDraft {
    var d = DecisionDraft()
    d.title = title
    d.desiredOutcome = outcome
    return d
}

/// The same fractional-second codec the shipping repository uses.
enum TestCodec {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(formatter.string(from: date))
        }
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let text = try c.decode(String.self)
            if let v = formatter.date(from: text) { return v }
            if let v = plainFormatter.date(from: text) { return v }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: text)
        }
        return d
    }
}
