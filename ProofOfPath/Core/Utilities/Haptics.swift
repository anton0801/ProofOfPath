//
//  Haptics.swift
//  ProofOfPath
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum Haptics {

    /// Set from settings so the user can silence feedback.
    static var isEnabled: Bool = true

    static func tap() {
        #if canImport(UIKit)
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func selection() {
        #if canImport(UIKit)
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func error() {
        #if canImport(UIKit)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
