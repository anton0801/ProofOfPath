//
//  APIError.swift
//  ProofOfPath
//

import Foundation

enum APIError: Error, Equatable, LocalizedError {
    /// The server could not be reached: no network, DNS, TLS, timeout.
    case offline
    /// The server answered with an error body.
    case server(status: Int, code: String, message: String, operationIndex: Int?)
    /// The device could not be signed in.
    case unauthorized
    /// The response was not what the API documents.
    case invalidResponse(String)
    /// A file that has to be uploaded is not on the device any more.
    case fileMissing(String)
    /// The Keychain refused to store the device identity.
    case credentialsUnavailable

    var isConnectivity: Bool {
        switch self {
        case .offline: return true
        case .server(let status, _, _, _): return status == 502 || status == 503 || status == 504
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You're offline. Check your internet connection and try again."
        case .server(let status, let code, let message, _):
            switch (status, code) {
            case (_, "storage_quota_exceeded"):
                return message
            case (413, _):
                return "That is too large to upload."
            case (429, _):
                return "Too many requests. Wait a moment and try again."
            case (500..., _):
                return "The ProofPath server had a problem. Try again in a moment."
            default:
                return message.isEmpty ? "The server refused the change." : message
            }
        case .unauthorized:
            return "This device could not be signed in to ProofPath."
        case .invalidResponse:
            return "The server sent an unexpected response. Try again, or update the app."
        case .fileMissing:
            return "An attached file is no longer on this device. Attach it again."
        case .credentialsUnavailable:
            return "The device identity could not be stored in the Keychain."
        }
    }

    static func from(_ error: Error) -> APIError {
        if let apiError = error as? APIError { return apiError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .invalidResponse("cancelled")
            default:
                // Every other transport failure — no route, DNS, TLS, timeout,
                // a dropped connection — means the server is out of reach.
                return .offline
            }
        }
        return .invalidResponse(String(describing: error))
    }
}

/// `{"error": {"code", "message", "details"}}`
struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        struct Details: Decodable {
            struct Operation: Decodable { let index: Int? }
            let operation: Operation?
        }
        let code: String
        let message: String
        let details: Details?
    }
    let error: Body
}
