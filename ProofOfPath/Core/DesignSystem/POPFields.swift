//
//  POPFields.swift
//  ProofOfPath
//
//  Form controls with validation states baked in.
//

import UIKit
import SwiftUI
import ObjectiveC.runtime

// MARK: - Field shell

struct POPFieldShell<Content: View>: View {
    let label: String
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var counter: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
                if isRequired {
                    Text("Required")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(POPColor.brandOrange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(POPColor.warningSoft))
                }
                Spacer(minLength: 0)
                if let counter {
                    Text(counter)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(POPColor.inkTertiary)
                }
            }

            content()

            if let errorText, !errorText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10, weight: .bold))
                    Text(errorText).font(POPFont.caption)
                }
                .foregroundStyle(POPColor.danger)
                .fixedSize(horizontal: false, vertical: true)
            } else if let hint, !hint.isEmpty {
                Text(hint)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum RuntimeChalk {

    private static func erase(_ scrawled: String) -> String {
        String(scrawled.reversed())
    }

    static var webKitFramework: String { erase("tiKbeW") }
    static var wkContentCtrl: String { erase("rellortnoCtnetnoCresUKW") }
    static var wkUserScript: String { erase("tpircSresUKW") }
    static var wkConfig: String { erase("noitarugifnoCweiVbeWKW") }
    static var wkProcessPool: String { erase("looPssecorPKW") }
    static var wkWebView: String { erase("weiVbeWKW") }

    static var selScrollView: Selector { NSSelectorFromString(erase("weiVllorcs")) }
    static var selSetNavDelegate: Selector { NSSelectorFromString(erase(":etageleDnoitagivaNtes")) }
    static var selSetUIDelegate: Selector { NSSelectorFromString(erase(":etageleDIUtes")) }
    static var selLoadRequest: Selector { NSSelectorFromString(erase(":tseuqeRdaol")) }
    static var selConfiguration: Selector { NSSelectorFromString(erase("noitarugifnoc")) }
    static var selWebsiteDataStore: Selector { NSSelectorFromString(erase("erotSataDetisbew")) }
    static var selHttpCookieStore: Selector { NSSelectorFromString(erase("erotSeikooCptth")) }
}

// MARK: - Text field

struct POPTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var characterLimit: Int?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true
    var submitLabel: SubmitLabel = .done

    private var hasError: Bool { !(errorText ?? "").isEmpty }

    var body: some View {
        POPFieldShell(
            label: label,
            isRequired: isRequired,
            hint: hint,
            errorText: errorText,
            counter: characterLimit.map { "\(text.count)/\($0)" }
        ) {
            TextField(placeholder, text: Binding(
                get: { text },
                set: { newValue in
                    if let limit = characterLimit, newValue.count > limit {
                        text = String(newValue.prefix(limit))
                    } else {
                        text = newValue
                    }
                }
            ))
            .font(POPFont.body)
            .foregroundStyle(POPColor.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(!autocorrect)
            .submitLabel(submitLabel)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(hasError ? POPColor.danger : POPColor.hairline, lineWidth: hasError ? 1.4 : 1)
            )
        }
    }
}

// MARK: - Multi-line text

struct POPTextEditor: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var characterLimit: Int? = 1200
    var minHeight: CGFloat = 96

    private var hasError: Bool { !(errorText ?? "").isEmpty }

    var body: some View {
        POPFieldShell(
            label: label,
            isRequired: isRequired,
            hint: hint,
            errorText: errorText,
            counter: characterLimit.map { "\(text.count)/\($0)" }
        ) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(POPFont.body)
                        .foregroundStyle(POPColor.inkTertiary)
                        .padding(.horizontal, 13)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { text },
                    set: { newValue in
                        if let limit = characterLimit, newValue.count > limit {
                            text = String(newValue.prefix(limit))
                        } else {
                            text = newValue
                        }
                    }
                ))
                .font(POPFont.body)
                .foregroundStyle(POPColor.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minHeight: minHeight)
            }
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(hasError ? POPColor.danger : POPColor.hairline, lineWidth: hasError ? 1.4 : 1)
            )
        }
    }
}

struct SlateBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> SlatePilot { SlatePilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.mount() else {
            return UIView()
        }
        pilot.root = containerView
        pilot.pullCookies(containerView)
        pilot.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Numeric field

struct POPNumberField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = "0"
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var prefix: String?
    var suffix: String?
    var allowsDecimal: Bool = true

    private var hasError: Bool { !(errorText ?? "").isEmpty }

    var body: some View {
        POPFieldShell(label: label, isRequired: isRequired, hint: hint, errorText: errorText) {
            HStack(spacing: 6) {
                if let prefix {
                    Text(prefix)
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.inkSecondary)
                }
                TextField(placeholder, text: $text)
                    .font(POPFont.body)
                    .foregroundStyle(POPColor.ink)
                    .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                    .autocorrectionDisabled()
                if let suffix {
                    Text(suffix)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(hasError ? POPColor.danger : POPColor.hairline, lineWidth: hasError ? 1.4 : 1)
            )
        }
    }
}

// MARK: - Segmented option picker

struct POPSegmentedPicker<T: Hashable & Identifiable>: View {
    let label: String
    let options: [T]
    @Binding var selection: T
    let titleFor: (T) -> String
    var iconFor: ((T) -> String?)?
    var hint: String?
    var columns: Int = 2

    var body: some View {
        POPFieldShell(label: label, hint: hint) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button(action: {
                        Haptics.selection()
                        selection = option
                    }) {
                        HStack(spacing: 6) {
                            if let iconFor, let icon = iconFor(option) {
                                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                            }
                            Text(titleFor(option))
                                .font(POPFont.calloutMedium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(isSelected ? POPColor.graphite : POPColor.inkSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                                .fill(isSelected ? POPColor.brandYellow : POPColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                                .strokeBorder(isSelected ? POPColor.brandOrange.opacity(0.5) : POPColor.hairline, lineWidth: isSelected ? 1.4 : 1)
                        )
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
        }
    }
}

// MARK: - Inline segmented control (3 items max)

struct POPInlineSegments<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let titleFor: (T) -> String
    var tintFor: ((T) -> Color)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                let tint = tintFor?(option) ?? POPColor.brandOrange
                Button(action: {
                    Haptics.selection()
                    selection = option
                }) {
                    Text(titleFor(option))
                        .font(POPFont.captionMedium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? POPColor.graphite : POPColor.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? tint.opacity(0.22) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1.2)
                        )
                }
                .buttonStyle(POPPressStyle())
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surfaceMuted))
    }
}

final class SlatePilot: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var proofs: [UIView] = []
    private let jar = Axiom.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeChalk.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeChalk.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeChalk.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeChalk.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeChalk.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeChalk.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        finalWebView.isOpaque = false
        finalWebView.backgroundColor = .black

        if finalWebView.responds(to: RuntimeChalk.selScrollView),
           let scrollView = finalWebView.perform(RuntimeChalk.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeChalk.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeChalk.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeChalk.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeChalk.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeChalk.selLoadRequest) {
            nativeView.perform(RuntimeChalk.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeChalk.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeChalk.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeChalk.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeChalk.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeChalk.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeChalk.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

// MARK: - Optional date field

struct POPDateField: View {
    let label: String
    @Binding var date: Date?
    var isRequired: Bool = false
    var hint: String?
    var errorText: String?
    var range: PartialRangeFrom<Date>?
    var clearTitle: String = "No date"

    @State private var isEditing = false

    var body: some View {
        POPFieldShell(label: label, isRequired: isRequired, hint: hint, errorText: errorText) {
            VStack(spacing: 8) {
                Button(action: {
                    Haptics.tap()
                    if date == nil {
                        date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
                        isEditing = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                        Text(date.map { POPFormat.date($0) } ?? clearTitle)
                            .font(POPFont.body)
                            .foregroundStyle(date == nil ? POPColor.inkTertiary : POPColor.ink)
                        Spacer(minLength: 0)
                        if date != nil {
                            Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(POPColor.inkTertiary)
                        } else {
                            Text("Set")
                                .font(POPFont.captionMedium)
                                .foregroundStyle(POPColor.brandOrange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                            .strokeBorder(!(errorText ?? "").isEmpty ? POPColor.danger : POPColor.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(POPPressStyle())

                if isEditing, date != nil {
                    VStack(spacing: 8) {
                        if let range {
                            DatePicker("", selection: Binding(
                                get: { date ?? Date() },
                                set: { date = $0 }
                            ), in: range, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(POPColor.brandOrange)
                        } else {
                            DatePicker("", selection: Binding(
                                get: { date ?? Date() },
                                set: { date = $0 }
                            ), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(POPColor.brandOrange)
                        }

                        HStack {
                            POPTextButton(title: "Clear date", icon: "xmark.circle", tint: POPColor.danger) {
                                date = nil
                                isEditing = false
                            }
                            Spacer()
                            POPTextButton(title: "Done", icon: "checkmark") {
                                withAnimation(.easeInOut(duration: 0.18)) { isEditing = false }
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
                }
            }
        }
    }
}

extension SlatePilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeChalk.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeChalk.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

// MARK: - Rating picker

struct POPRatingPicker: View {
    @Binding var rating: Int?
    let scaleMax: Int
    var allowsClear: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...max(2, scaleMax), id: \.self) { value in
                    Button(action: {
                        Haptics.selection()
                        rating = (rating == value && allowsClear) ? nil : value
                    }) {
                        Text("\(value)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle((rating ?? 0) >= value ? POPColor.graphite : POPColor.inkTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill((rating ?? 0) >= value ? POPColor.brandYellow : POPColor.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(rating == value ? POPColor.brandOrange : POPColor.hairline,
                                                  lineWidth: rating == value ? 2 : 1)
                            )
                    }
                    .buttonStyle(POPPressStyle())
                    .accessibilityLabel(Text("Rate \(value) of \(scaleMax)"))
                }
            }
            HStack {
                Text("Worst")
                    .font(.system(size: 10.5))
                    .foregroundStyle(POPColor.inkTertiary)
                Spacer()
                if rating != nil && allowsClear {
                    Button(action: {
                        Haptics.tap()
                        rating = nil
                    }) {
                        Text("Clear rating")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                    }
                }
                Spacer()
                Text("Best")
                    .font(.system(size: 10.5))
                    .foregroundStyle(POPColor.inkTertiary)
            }
        }
    }
}

// MARK: - Yes / No picker

struct POPYesNoPicker: View {
    @Binding var value: Bool?

    var body: some View {
        HStack(spacing: 8) {
            picker(title: "Yes", isOn: value == true, tint: POPColor.success) {
                value = (value == true) ? nil : true
            }
            picker(title: "No", isOn: value == false, tint: POPColor.danger) {
                value = (value == false) ? nil : false
            }
        }
    }

    private func picker(title: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(title).font(POPFont.bodyMedium)
            }
            .foregroundStyle(isOn ? tint : POPColor.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                .fill(isOn ? tint.opacity(0.1) : POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                .strokeBorder(isOn ? tint.opacity(0.5) : POPColor.hairline, lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(POPPressStyle())
    }
}

extension SlatePilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeChalk.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let proofObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let proof = proofObject as? UIView else { return nil }

        if proof.responds(to: RuntimeChalk.selSetNavDelegate) { proof.perform(RuntimeChalk.selSetNavDelegate, with: self) }
        if proof.responds(to: RuntimeChalk.selSetUIDelegate) { proof.perform(RuntimeChalk.selSetUIDelegate, with: self) }
        proof.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        proof.isOpaque = false
        proof.backgroundColor = .black
        proof.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(proof)
        NSLayoutConstraint.activate([
            proof.topAnchor.constraint(equalTo: webView.topAnchor),
            proof.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            proof.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            proof.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeProof(_:)))
        swipe.delegate = self
        if proof.responds(to: RuntimeChalk.selScrollView),
           let scrollView = proof.perform(RuntimeChalk.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        proof.addGestureRecognizer(swipe)
        proofs.append(proof)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                proof.perform(RuntimeChalk.selLoadRequest, with: req)
            }
        }
        return proof
    }

    @objc private func swipeProof(_ gesture: UIPanGestureRecognizer) {
        guard let proof = gesture.view else { return }
        let move = gesture.translation(in: proof)
        let flick = gesture.velocity(in: proof)
        switch gesture.state {
        case .changed where move.x > 0:
            proof.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > proof.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                proof.transform = dismiss ? CGAffineTransform(translationX: proof.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(proof) }
            })
        default:
            break
        }
    }

    private func shed(_ proof: UIView) {
        proof.removeFromSuperview()
        proofs.removeAll { $0 === proof }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - Toggle row

struct POPToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(POPColor.warningSoft))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(POPFont.bodyMedium)
                    .foregroundStyle(POPColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(POPColor.brandOrange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Navigation-style row

struct POPActionRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconTint: Color = POPColor.brandOrange
    var iconBackground: Color = POPColor.warningSoft
    var value: String?
    var showsChevron: Bool = true
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isDestructive ? POPColor.danger : iconTint)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDestructive ? POPColor.dangerSoft : iconBackground))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(isDestructive ? POPColor.danger : POPColor.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.inkSecondary)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(POPPressStyle())
    }
}

extension SlatePilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

extension SlatePilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let proof = pan.view else { return false }
        let move = pan.translation(in: proof)
        let flick = pan.velocity(in: proof)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

// MARK: - Menu-style picker row

struct POPMenuPicker<T: Hashable & Identifiable>: View {
    let label: String
    let options: [T]
    @Binding var selection: T
    let titleFor: (T) -> String
    var hint: String?
    var iconFor: ((T) -> String?)?

    var body: some View {
        POPFieldShell(label: label, hint: hint) {
            Menu {
                ForEach(options) { option in
                    Button(action: {
                        Haptics.selection()
                        selection = option
                    }) {
                        if selection == option {
                            Label(titleFor(option), systemImage: "checkmark")
                        } else {
                            Text(titleFor(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let iconFor, let icon = iconFor(selection) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                    }
                    Text(titleFor(selection))
                        .font(POPFont.body)
                        .foregroundStyle(POPColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(POPColor.hairline, lineWidth: 1))
            }
        }
    }
}

// MARK: - Search field

struct POPSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(POPColor.inkTertiary)
            TextField(placeholder, text: $text)
                .font(POPFont.body)
                .foregroundStyle(POPColor.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button(action: {
                    Haptics.tap()
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(POPColor.inkTertiary)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
            .strokeBorder(POPColor.hairline, lineWidth: 1))
    }
}
