//
//  Formatters.swift
//  ProofOfPath
//

import Foundation

enum POPFormat {

    // MARK: Dates

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f
    }()

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    static func date(_ date: Date) -> String { mediumDate.string(from: date) }
    static func dateShort(_ date: Date) -> String { shortDate.string(from: date) }
    static func dateTime(_ date: Date) -> String { dateTime.string(from: date) }

    static func optionalDate(_ date: Date?, placeholder: String = "Not set") -> String {
        guard let date else { return placeholder }
        return mediumDate.string(from: date)
    }

    /// Whole days between the start of today and the start of `date`.
    static func daysUntil(_ date: Date, from reference: Date = Date()) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: reference)
        let b = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// "in 4 days", "today", "3 days overdue"
    static func relativeDeadline(_ date: Date, from reference: Date = Date()) -> String {
        let days = daysUntil(date, from: reference)
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        if days == -1 { return "1 day overdue" }
        if days < 0 { return "\(-days) days overdue" }
        return "In \(days) days"
    }

    static func relativeTimestamp(_ date: Date, from reference: Date = Date()) -> String {
        let seconds = reference.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        let days = daysUntil(reference, from: date)
        if days <= 7 { return "\(max(1, days)) d ago" }
        return mediumDate.string(from: date)
    }

    // MARK: Money

    static func money(_ value: Double, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = (value.rounded() == value) ? 0 : 2
        f.minimumFractionDigits = 0
        if let s = f.string(from: NSNumber(value: value)) { return s }
        return "\(currencySymbol(for: currencyCode))\(decimal(value))"
    }

    static func moneyOptional(_ value: Double?, currencyCode: String, placeholder: String = "—") -> String {
        guard let value else { return placeholder }
        return money(value, currencyCode: currencyCode)
    }

    /// Scanning every available locale is far too slow for a view body, and the
    /// answer never changes — resolve once per code and keep it.
    private static var currencySymbolCache: [String: String] = [:]

    static func currencySymbol(for code: String) -> String {
        if let cached = currencySymbolCache[code] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let symbol = formatter.currencySymbol ?? code
        // Some codes resolve to the code itself; that is still a usable label.
        currencySymbolCache[code] = symbol
        return symbol
    }

    // MARK: Numbers

    static func decimal(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = maxFractionDigits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Plain, ungrouped text for pre-filling an editable numeric field.
    /// Grouping separators must never reach a text field: in a locale where the
    /// group separator is ".", re-parsing "1.249" would silently produce 1.249.
    static func editableNumber(_ value: Double, maxFractionDigits: Int = 4) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.groupingSeparator = ""
        f.decimalSeparator = "."
        f.maximumFractionDigits = maxFractionDigits
        f.minimumFractionDigits = 0
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func editableNumber(_ value: Double?) -> String {
        guard let value else { return "" }
        return editableNumber(value)
    }

    static func percent(_ value: Double, maxFractionDigits: Int = 1) -> String {
        "\(decimal(value, maxFractionDigits: maxFractionDigits))%"
    }

    static func score(_ value: Double) -> String {
        decimal(value, maxFractionDigits: 1)
    }

    // MARK: Parsing

    /// Accepts "1 200,50", "1,200.50", "1200.5".
    static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var cleaned = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "'", with: "")
        // If both separators appear, the last one is the decimal separator.
        if cleaned.contains(",") && cleaned.contains(".") {
            if let lastComma = cleaned.lastIndex(of: ","), let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        return Double(cleaned)
    }

    static func fileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - String helpers

extension String {
    var popTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var popIsBlank: Bool { popTrimmed.isEmpty }

    /// Collapses whitespace and lowercases — used for duplicate-name detection.
    var popNormalizedForCompare: String {
        popTrimmed.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func popTruncated(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}

extension Optional where Wrapped == String {
    var popOrEmpty: String { self ?? "" }
}

// MARK: - Collection helpers

extension Collection {
    subscript(popSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
