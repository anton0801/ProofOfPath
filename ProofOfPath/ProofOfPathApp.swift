//
//  ProofOfPathApp.swift
//  ProofOfPath
//

import SwiftUI

@main
struct ProofOfPathApp: App {

    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.light)
                .tint(POPColor.brandOrange)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                store.flush()
            }
        }
    }
}
