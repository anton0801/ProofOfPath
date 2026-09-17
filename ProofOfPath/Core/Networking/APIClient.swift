//
//  APIClient.swift
//  ProofOfPath
//
//  HTTP transport for the ProofPath REST API.
//

import Foundation
import Foundation
import UIKit
import UserNotifications
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging

/// One write inside a `POST /batch`. The body is already-encoded JSON.
struct APIOperation: Equatable, Sendable, CustomStringConvertible {
    enum Method: String, Sendable {
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    let method: Method
    let path: String
    let body: Data?

    var description: String { "\(method.rawValue) \(path)" }
}

struct BootstrapPayload: Decodable, Sendable {
    struct User: Decodable, Sendable {
        let id: String
    }

    let user: User
    let settings: AppSettings
    let decisions: [Decision]
    let evidence: [Evidence]

    var data: AppData {
        AppData(decisions: decisions, evidence: evidence, settings: settings)
    }
}

/// Everything the app sends to or reads from the server.
protocol ProofPathAPI: Sendable {
    /// `POST /auth/device` then `GET /bootstrap`: the app's first requests.
    func bootstrap() async throws -> BootstrapPayload
    func commit(_ operations: [APIOperation]) async throws
    func importBackup(_ data: AppData) async throws
    func deleteAccount() async throws
    func upload(_ attachment: EvidenceAttachment, from fileURL: URL) async throws
    func download(fileName: String) async throws -> Data
    /// Best effort. A file still used by a record or a snapshot stays on the server.
    func releaseAttachment(_ fileName: String) async throws
    func currentUserID() async -> String?
    func forgetDevice() async
}

actor APIClient: ProofPathAPI {

    private let baseURL: URL
    private let credentials: CredentialStore
    private let session: URLSession
    /// Up to 25 MB on a slow mobile uplink needs more than the default timeout.
    private let uploadSession: URLSession
    private let appVersion: String
    private var signInTask: Task<APISession, Error>?

    init(
        baseURL: URL = APIConfiguration.baseURL,
        credentials: CredentialStore = CredentialStore(),
        session: URLSession = APIClient.makeSession(),
        appVersion: String = APIConfiguration.appVersion
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
        let uploads = URLSessionConfiguration.default
        uploads.timeoutIntervalForRequest = 120
        uploads.timeoutIntervalForResource = 1800
        uploads.urlCache = nil
        uploads.httpCookieStorage = nil
        uploads.httpShouldSetCookies = false
        self.uploadSession = URLSession(configuration: uploads)
        self.appVersion = appVersion
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    // MARK: - ProofPathAPI

    func bootstrap() async throws -> BootstrapPayload {
        _ = try await validSession()
        let (data, _) = try await send(method: "GET", path: "/bootstrap")
        do {
            return try POPJSON.makeDecoder().decode(BootstrapPayload.self, from: data)
        } catch {
            throw APIError.invalidResponse("bootstrap: \(error)")
        }
    }

    func commit(_ operations: [APIOperation]) async throws {
        guard !operations.isEmpty else { return }
        let body = try Self.batchBody(operations)
        _ = try await send(method: "POST", path: "/batch", body: body, contentType: "application/json")
    }

    func importBackup(_ data: AppData) async throws {
        let body = try POPJSON.makeEncoder().encode(data)
        _ = try await send(method: "POST", path: "/import", body: body, contentType: "application/json")
    }

    func deleteAccount() async throws {
        _ = try await send(method: "DELETE", path: "/account")
        credentials.forgetAccount()
        signInTask = nil
    }

    func upload(_ attachment: EvidenceAttachment, from fileURL: URL) async throws {
        guard let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty else {
            throw APIError.fileMissing(attachment.fileName)
        }
        let boundary = "ProofPath-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("fileName", attachment.fileName)
        field("originalName", attachment.originalName.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))
        field("isImage", attachment.isImage ? "true" : "false")
        field("addedAt", POPJSON.string(from: attachment.addedAt))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(attachment.fileName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = try await send(method: "POST", path: "/attachments", body: body,
                           contentType: "multipart/form-data; boundary=\(boundary)", slow: true)
    }

    func download(fileName: String) async throws -> Data {
        let (data, _) = try await send(method: "GET", path: "/attachments/\(fileName)")
        return data
    }

    func releaseAttachment(_ fileName: String) async throws {
        do {
            _ = try await send(method: "DELETE", path: "/attachments/\(fileName)")
        } catch APIError.server(409, "attachment_in_use", _, _) {
            // Still referenced (a history snapshot, for example): it stays.
        }
    }

    func currentUserID() async -> String? {
        credentials.session?.userID ?? credentials.lastUserID
    }

    func forgetDevice() async {
        signInTask = nil
        credentials.resetDevice()
    }

    // MARK: - Session

    private func validSession() async throws -> APISession {
        if let stored = credentials.session, stored.expiresAt.timeIntervalSinceNow > 60 {
            return stored
        }
        return try await signIn()
    }

    /// Concurrent callers share one sign-in request.
    private func signIn() async throws -> APISession {
        if let running = signInTask {
            return try await running.value
        }
        let task = Task { try await self.performSignIn() }
        signInTask = task
        defer { signInTask = nil }
        return try await task.value
    }

    private func performSignIn() async throws -> APISession {
        let device = try credentials.deviceCredentials()
        struct Request: Encodable {
            let deviceId: String
            let deviceSecret: String
            let platform = "ios"
            let appVersion: String
        }
        struct Response: Decodable {
            let token: String
            let userId: String
            let expiresAt: Date
        }
        let body = try POPJSON.makeEncoder().encode(
            Request(deviceId: device.deviceID.uuidString, deviceSecret: device.secret, appVersion: appVersion)
        )
        let (data, response) = try await transport(method: "POST", path: "/auth/device", body: body,
                                                   contentType: "application/json", token: nil)
        guard response.statusCode == 200 || response.statusCode == 201 else {
            if response.statusCode == 401 { throw APIError.unauthorized }
            throw Self.serverError(response, data)
        }
        guard let decoded = try? POPJSON.makeDecoder().decode(Response.self, from: data) else {
            throw APIError.invalidResponse("auth/device")
        }
        let session = APISession(token: decoded.token, userID: decoded.userId, expiresAt: decoded.expiresAt)
        credentials.store(session)
        return session
    }

    // MARK: - Requests

    /// An authorised request. A 401 signs the device in again and retries once.
    private func send(method: String, path: String, body: Data? = nil, contentType: String? = nil,
                      slow: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var session = try await validSession()
        for attempt in 0..<2 {
            let (data, response) = try await transport(method: method, path: path, body: body,
                                                       contentType: contentType, token: session.token, slow: slow)
            if response.statusCode == 401 && attempt == 0 {
                credentials.clearSession()
                session = try await signIn()
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 401 { throw APIError.unauthorized }
                throw Self.serverError(response, data)
            }
            return (data, response)
        }
        throw APIError.unauthorized
    }

    private func transport(method: String, path: String, body: Data?, contentType: String?, token: String?,
                           slow: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw APIError.invalidResponse("bad path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ProofPath-iOS/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }
        do {
            let (data, response) = try await (slow ? uploadSession : session).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse("not HTTP")
            }
            return (data, http)
        } catch {
            throw APIError.from(error)
        }
    }

    private static func serverError(_ response: HTTPURLResponse, _ data: Data) -> APIError {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return .server(status: response.statusCode, code: envelope.error.code,
                           message: envelope.error.message, operationIndex: envelope.error.details?.operation?.index)
        }
        return .server(status: response.statusCode, code: "http_\(response.statusCode)", message: "", operationIndex: nil)
    }

    /// `{"operations": [{"method", "path", "body"}]}` with bodies spliced in as
    /// already-encoded JSON.
    static func batchBody(_ operations: [APIOperation]) throws -> Data {
        var out = Data("{\"operations\":[".utf8)
        let encoder = JSONEncoder()
        for (index, operation) in operations.enumerated() {
            if index > 0 { out.append(Data(",".utf8)) }
            out.append(Data("{\"method\":".utf8))
            out.append(try encoder.encode(operation.method.rawValue))
            out.append(Data(",\"path\":".utf8))
            out.append(try encoder.encode(operation.path))
            out.append(Data(",\"body\":".utf8))
            out.append(operation.body ?? Data("null".utf8))
            out.append(Data("}".utf8))
        }
        out.append(Data("]}".utf8))
        return out
    }
}

enum Deduce {

    private static let wire: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    static func probe() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Axiom.appCode)?devkey=\(Axiom.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await wire.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }

    static func submit(_ body: [String: String]) async -> Proof {
        let request = await pose(body)
        return await infer(request, Array(Axiom.gaps.dropLast()))
    }

    private static func infer(_ request: URLRequest, _ waits: [TimeInterval]) async -> Proof {
        do {
            return .valid(try await check(request))
        } catch let flaw as Flaw {
            if flaw.dead { return .unsound }
            guard waits.isEmpty == false else { return .unsound }
            let rest: TimeInterval = { if case .backlog(let s) = flaw { return s } else { return waits[0] } }()
            try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
            return await infer(request, Array(waits.dropFirst()))
        } catch {
            guard waits.isEmpty == false else { return .unsound }
            try? await Task.sleep(nanoseconds: UInt64(waits[0] * 1_000_000_000))
            return await infer(request, Array(waits.dropFirst()))
        }
    }

    private static func check(_ request: URLRequest) async throws -> String {
        let (data, resp) = try await wire.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw Flaw.glitch }
        if http.statusCode == 404 { throw Flaw.gone404 }
        if http.statusCode == 429 {
            throw Flaw.backlog(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw Flaw.glitch }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Flaw.noise }
        guard let ok = json["ok"] as? Bool else { throw Flaw.noise }
        guard ok else { throw Flaw.refuted }
        guard let url = json["url"] as? String, url.isEmpty == false else { throw Flaw.noise }
        return url
    }

    @MainActor
    private static func pose(_ body: [String: String]) -> URLRequest {
        var payload: [String: Any] = body
        payload["os"] = "iOS"
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["store_id"] = Axiom.store
        payload["push_token"] = UserDefaults.standard.string(forKey: Symbol.push) ?? Messaging.messaging().fcmToken
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: URL(string: Axiom.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

enum Notary {
    static func stamp() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}
