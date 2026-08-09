//
//  PDFComposer.swift
//  ProofOfPath
//
//  Renders a decision summary to a real, selectable-text PDF.
//  Only user data and the creation date appear in the export.
//

import Foundation
#if canImport(UIKit)
import UIKit

enum PDFBlock {
    case title(String)
    case subtitle(String)
    case heading(String)
    case body(String)
    case keyValue(String, String)
    case bullet(String)
    case spacer(CGFloat)
    case rule
}

enum PDFComposer {

    private static let pageSize = CGSize(width: 595, height: 842)   // A4 at 72 dpi
    private static let margin: CGFloat = 48

    static func makePDF(fileName: String, blocks: [PDFBlock]) throws -> URL {
        // Prefixed so the shared temp copy is cleaned up with the other exports.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProofPath-Summary-\(sanitize(fileName)).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            var cursorY = margin
            context.beginPage()

            func newPageIfNeeded(_ height: CGFloat) {
                if cursorY + height > pageSize.height - margin {
                    context.beginPage()
                    cursorY = margin
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat, indent: CGFloat = 0) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                paragraph.lineSpacing = 2

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let maxWidth = pageSize.width - margin * 2 - indent
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let bounding = attributed.boundingRect(
                    with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                newPageIfNeeded(bounding.height)
                attributed.draw(with: CGRect(x: margin + indent, y: cursorY, width: maxWidth, height: bounding.height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                context: nil)
                cursorY += bounding.height + spacingAfter
            }

            for block in blocks {
                switch block {
                case .title(let text):
                    draw(text, font: .systemFont(ofSize: 24, weight: .bold), color: .black, spacingAfter: 6)

                case .subtitle(let text):
                    draw(text, font: .systemFont(ofSize: 12, weight: .regular), color: .darkGray, spacingAfter: 16)

                case .heading(let text):
                    cursorY += 8
                    draw(text.uppercased(), font: .systemFont(ofSize: 10, weight: .bold), color: .darkGray, spacingAfter: 6)

                case .body(let text):
                    guard !text.isEmpty else { continue }
                    draw(text, font: .systemFont(ofSize: 11.5, weight: .regular), color: .black, spacingAfter: 8)

                case .keyValue(let key, let value):
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineSpacing = 2
                    let combined = NSMutableAttributedString(
                        string: "\(key):  ",
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                            .foregroundColor: UIColor.darkGray,
                            .paragraphStyle: paragraph
                        ]
                    )
                    combined.append(NSAttributedString(
                        string: value.isEmpty ? "—" : value,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 11.5, weight: .regular),
                            .foregroundColor: UIColor.black,
                            .paragraphStyle: paragraph
                        ]
                    ))
                    let maxWidth = pageSize.width - margin * 2
                    let bounding = combined.boundingRect(
                        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    newPageIfNeeded(bounding.height)
                    combined.draw(with: CGRect(x: margin, y: cursorY, width: maxWidth, height: bounding.height),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    cursorY += bounding.height + 5

                case .bullet(let text):
                    draw("•  \(text)", font: .systemFont(ofSize: 11.5, weight: .regular), color: .black,
                         spacingAfter: 4, indent: 8)

                case .spacer(let height):
                    newPageIfNeeded(height)
                    cursorY += height

                case .rule:
                    newPageIfNeeded(12)
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: cursorY + 4))
                    path.addLine(to: CGPoint(x: pageSize.width - margin, y: cursorY + 4))
                    UIColor(white: 0.85, alpha: 1).setStroke()
                    path.lineWidth = 0.8
                    path.stroke()
                    cursorY += 14
                }
            }
        }

        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = name.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "ProofPath-Summary" : String(trimmed.prefix(60))
    }
}
#endif
