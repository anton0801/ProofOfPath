//
//  POPJSON.swift
//  ProofOfPath
//
//  One JSON dialect for the data file, backups and the API.
//
//  Dates are ISO-8601 with fractional seconds. Plain `.iso8601` truncates to
//  whole seconds, which lets two events logged in the same second swap places
//  after a round trip. Decoding also accepts whole-second dates, so files and
//  server responses written without fractions still read.
//

import Foundation

enum POPJSON {

    private static let precise: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        precise.string(from: date)
    }

    static func date(from text: String) -> Date? {
        precise.date(from: text) ?? wholeSeconds.date(from: text)
    }

    /// Compact output for the wire and the data file.
    static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(POPJSON.string(from: date))
        }
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = POPJSON.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "“\(text)” is not an ISO-8601 date."
                )
            }
            return date
        }
        return decoder
    }
}
