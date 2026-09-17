//
//  ProofOfPathApp.swift
//  ProofOfPath
//

import SwiftUI

@main
struct ProofOfPathApp: App {

    @StateObject private var store = AppStore()
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            // Scene-phase changes are handled in RootView: the scene-level
            // onChange with old and new values needs iOS 17.
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(POPColor.brandOrange)
        }
    }
}
