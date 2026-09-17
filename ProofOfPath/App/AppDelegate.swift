import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private var whole: [AnyHashable: Any] = [:]
    private var part: [AnyHashable: Any] = [:]
    private var hold: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Axiom.relayKey
        sdk.appleAppID = Axiom.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            parse(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(stirred), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func stirred() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Symbol.attStatus)
            }
        }
    }

    private func pause() {
        hold?.cancel()
        hold = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.conclude() }
        }
    }

    private func conclude() {
        hold?.cancel()
        hold = nil
        var whole = self.whole
        for (key, value) in part {
            let tag = "deep_\(key)"
            if whole[tag] == nil { whole[tag] = value }
        }
        NotificationCenter.default.post(name: .proven, object: nil, userInfo: ["conversionData": whole])
    }

    private func parse(_ payload: [AnyHashable: Any]) {
        var seen: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            seen = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            seen = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            seen = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            seen = url
        }
        guard let link = seen else { return }

        UserDefaults.standard.set(link, forKey: Symbol.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .chalked, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Symbol.fcm)
            UserDefaults.standard.set(token, forKey: Symbol.push)
            UserDefaults(suiteName: Axiom.suite)?.set(token, forKey: Symbol.sharedFcm)
        }
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        whole = conversionInfo
        pause()
        if part.isEmpty == false { conclude() }
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Symbol.primed) == false else { return }
        part = deepLink.clickEvent
        NotificationCenter.default.post(name: .cited, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        hold?.cancel()
        hold = nil
        if whole.isEmpty == false { conclude() }
    }
}


extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        parse(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        parse(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        parse(userInfo)
        completionHandler(.newData)
    }
}
