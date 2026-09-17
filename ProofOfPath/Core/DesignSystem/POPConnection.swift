//
//  POPConnection.swift
//  ProofOfPath
//
//  UI for a server-backed store: connecting, offline, saving.
//

import SwiftUI

// MARK: - Submitting from an editor

/// Sends one intent from an editor and reports when the server confirmed it.
///
/// Editors close only after a successful save, so a failed save never throws
/// away what the user typed. A second tap while a save is running is ignored.
@MainActor
final class POPSubmission: ObservableObject {
    @Published private(set) var isRunning = false

    func run(_ store: AppStore, _ intent: AppIntent, onSuccess: @escaping @MainActor () -> Void = {}) {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor in
            let saved = await store.perform(intent)
            isRunning = false
            if saved { onSuccess() }
        }
    }
}

/// A navigation-bar Save button that shows progress while the server works.
struct POPToolbarSaveButton: View {
    @EnvironmentObject private var store: AppStore
    var title: String = "Save"
    let isSaving: Bool
    /// Orange when the form is valid. The button stays tappable either way,
    /// so tapping an incomplete form can point at what is missing.
    var isHighlighted: Bool = true
    let action: () -> Void

    var body: some View {
        if isSaving {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(POPColor.brandOrange)
                .accessibilityLabel(Text("Saving"))
        } else {
            Button(title, action: action)
                .font(POPFont.bodyMedium)
                .foregroundStyle(isHighlighted && store.canEdit ? POPColor.brandOrange : POPColor.inkTertiary)
                .disabled(!store.canEdit)
        }
    }
}

// MARK: - Read-only while offline

private struct RequiresConnectionModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore

    func body(content: Content) -> some View {
        content
            .disabled(!store.canEdit)
            .opacity(store.canEdit ? 1 : 0.45)
    }
}

extension View {
    /// Disables a control that changes data while the server is out of reach.
    func popRequiresConnection() -> some View {
        modifier(RequiresConnectionModifier())
    }
}

// MARK: - Status banners

/// Shown above the tabs while the app is offline or reconnecting.
struct POPConnectionBanner: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.phase == .ready, store.connection != .online {
            HStack(spacing: 8) {
                if store.connection == .connecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(POPColor.graphite)
                    Text("Connecting…")
                        .font(POPFont.captionMedium)
                } else {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .bold))
                    Text(store.lastFailureWasNetwork ? "No connection — viewing saved data" : "Server unavailable — viewing saved data")
                        .font(POPFont.captionMedium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Button("Retry") { store.retryNow() }
                        .font(POPFont.captionMedium)
                        .foregroundStyle(POPColor.brandOrange)
                }
            }
            .foregroundStyle(POPColor.graphite)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(POPColor.sand)
            .overlay(alignment: .bottom) {
                Rectangle().fill(POPColor.hairline).frame(height: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

/// A small capsule while a change is on its way to the server.
struct POPSavingIndicator: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.isSaving {
            HStack(spacing: 7) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(POPColor.graphite)
                Text("Saving…")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.graphite)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(POPColor.surface))
            .overlay(Capsule().strokeBorder(POPColor.hairline, lineWidth: 1))
            .shadow(color: POPColor.graphite.opacity(0.08), radius: 8, y: 3)
            .transition(.opacity)
            .accessibilityLabel(Text("Saving"))
        }
    }
}

// MARK: - Full-screen states

/// First launch: signing the device in and loading its data.
struct POPConnectingView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image("screenMLoader")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .blur(radius: 8)
                
                VStack(spacing: 18) {
                    Spacer ()
                    
                    Image("proofs-icon")
                        .resizable()
                        .frame(width: 82, height: 82)
                        .cornerRadius(18)
                    
                    Text("Proofs Of Paths")
                        .font(POPFont.display(26))
                        .foregroundStyle(.white)
                    
                    Spacer ()
                    
                    HStack(spacing: 8) {
                        Image("screenLoaderImage")
                            .resizable()
                            .frame(width: 200, height: 50)
                        
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .ignoresSafeArea()
    }
}

/// Nothing cached yet and the server cannot be reached.
struct POPConnectionUnavailableView: View {
    @EnvironmentObject private var store: AppStore
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(POPColor.brandOrange)
                .frame(width: 70, height: 70)
                .background(Circle().fill(POPColor.sand))
            Text("Can't reach ProofPath")
                .font(POPFont.display(24))
                .foregroundStyle(POPColor.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(POPFont.body)
                .foregroundStyle(POPColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your decisions are stored in your ProofPath account. Connect to the internet to load them.")
                .font(POPFont.callout)
                .foregroundStyle(POPColor.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            POPPrimaryButton(title: "Try Again", icon: "arrow.clockwise",
                             isLoading: store.connection == .connecting) {
                store.retryNow()
            }
            .padding(.top, 6)
            .accessibilityIdentifier("connection.retry")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(POPColor.canvas.ignoresSafeArea())
    }
}
