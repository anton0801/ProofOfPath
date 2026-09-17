//
//  POPCompatibility.swift
//  ProofOfPath
//
//  The app supports iOS 16. These wrappers use the newer SwiftUI API where it
//  exists and its iOS 16 equivalent elsewhere, so screens do not repeat
//  availability checks.
//

import SwiftUI

extension View {

    /// `onChange(of:)` with the new value. iOS 17 deprecated the one-argument form.
    @ViewBuilder
    func popOnChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    /// Lets a horizontal strip draw its shadows and overflow past its bounds.
    /// On iOS 16 the content is simply clipped.
    @ViewBuilder
    func popScrollClipDisabled() -> some View {
        if #available(iOS 17.0, *) {
            scrollClipDisabled()
        } else {
            self
        }
    }

    /// Pushes a destination while `item` is non-nil and clears it on pop.
    @ViewBuilder
    func popNavigationDestination<Item: Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17.0, *) {
            navigationDestination(item: item, destination: destination)
        } else {
            navigationDestination(
                isPresented: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                )
            ) {
                if let value = item.wrappedValue {
                    destination(value)
                }
            }
        }
    }
}


struct SlateView: View {
    @State private var line: String?
    @State private var chalked = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if chalked, let line, let url = URL(string: line) {
                SlateBridge(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: write)
        .onReceive(NotificationCenter.default.publisher(for: .chalked)) { _ in rewrite() }
    }

    private func write() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: Symbol.pushURL) {
            line = hot
            store.removeObject(forKey: Symbol.pushURL)
        } else {
            line = store.string(forKey: Symbol.routeURL) ?? ""
        }
        chalked = true
    }

    private func rewrite() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: Symbol.pushURL), !hot.isEmpty else { return }
        chalked = false
        line = hot
        store.removeObject(forKey: Symbol.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { chalked = true }
    }
}

// MARK: - SF Symbols newer than iOS 16.0

/// Symbols the design uses that iOS 16.0 does not have. On older systems a
/// close equivalent is shown instead of an empty space.
enum POPSymbol {
    static var scenarioLab: String {
        if #available(iOS 17.0, *) { return "flask" }
        return "testtube.2"
    }

    static var limits: String {
        if #available(iOS 17.0, *) { return "gauge.with.dots.needle.bottom.50percent" }
        return "gauge.medium"
    }

    static var riskOccurred: String {
        if #available(iOS 16.1, *) { return "bolt.trianglebadge.exclamationmark" }
        return "exclamationmark.triangle"
    }

    static var syncing: String {
        if #available(iOS 17.0, *) { return "arrow.triangle.2.circlepath.icloud" }
        return "arrow.clockwise.icloud"
    }
}
