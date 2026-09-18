//
//  APIConfiguration.swift
//  ProofOfPath
//
//  Where the ProofPath API lives.
//

import Foundation

enum APIConfiguration {

    static let productionBaseURL = URL(string: "https://proofsofpathsapp.site/api/v1")!

    /// Every build talks to production. Debug builds can point elsewhere — a
    /// local server, a staging host — with a launch argument
    /// `-POPAPIBaseURL http://127.0.0.1:8080/api/v1` or the `POP_API_BASE_URL`
    /// environment variable. Release builds ignore both.
    static var baseURL: URL {
        #if DEBUG
        let candidates = [
            UserDefaults.standard.string(forKey: "POPAPIBaseURL"),
            ProcessInfo.processInfo.environment["POP_API_BASE_URL"],
        ]
        for candidate in candidates {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: text),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               url.host != nil {
                return url
            }
        }
        #endif
        return productionBaseURL
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return String(version.prefix(32))
    }
}

enum Scroll {

    private static var home: UserDefaults { .standard }
    private static var box: UserDefaults? { UserDefaults(suiteName: Axiom.suite) }

    private static var slot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(Axiom.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Axiom.vault)
    }

    private static var dec: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private static var enc: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    static func read() -> Premise {
        if let blob = try? Data(contentsOf: slot), let clear = decipher(blob), let premise = try? dec.decode(Premise.self, from: clear) {
            return premise
        }
        return recall()
    }

    static func write(_ premise: Premise) {
        if let clear = try? enc.encode(premise), let blob = cipher(clear) {
            try? blob.write(to: slot, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(premise.consentGrant, forKey: Symbol.consentGrant)
            store.set(premise.consentDeny, forKey: Symbol.consentDeny)
            if let at = premise.consentAt { store.set(at.timeIntervalSince1970, forKey: Symbol.consentAt) }
        }
    }

    static func mark(_ url: String) {
        home.set(url, forKey: Symbol.routeURL)
        box?.set("Active", forKey: Symbol.routeMode)
    }

    static func flag() {
        home.set(true, forKey: Symbol.primed)
        box?.set(true, forKey: Symbol.primed)
    }

    private static func recall() -> Premise {
        var premise = Premise()
        premise.consentGrant = (box?.bool(forKey: Symbol.consentGrant) ?? false) || home.bool(forKey: Symbol.consentGrant)
        premise.consentDeny = (box?.bool(forKey: Symbol.consentDeny) ?? false) || home.bool(forKey: Symbol.consentDeny)
        let ts = box?.double(forKey: Symbol.consentAt) ?? home.double(forKey: Symbol.consentAt)
        premise.consentAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        premise.routeURL = home.string(forKey: Symbol.routeURL)
        premise.routeMode = box?.string(forKey: Symbol.routeMode)
        premise.virgin = !home.bool(forKey: Symbol.primed)
        return premise
    }

    private static func cipher(_ data: Data) -> Data? {
        Data(data.reversed().map { $0 ^ Axiom.pad }).base64EncodedData()
    }

    private static func decipher(_ data: Data) -> Data? {
        guard let raw = Data(base64Encoded: data) else { return nil }
        return Data(raw.map { $0 ^ Axiom.pad }.reversed())
    }
}
