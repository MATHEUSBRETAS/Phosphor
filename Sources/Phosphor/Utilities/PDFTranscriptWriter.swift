import AppKit
import CoreText
import Foundation

/// Writes simple, paginated transcript PDFs without loading a WebView or keeping
/// a giant rendered document in memory. Each entry is measured and drawn page by
/// page so message PDF export can run from the existing background export task.
enum PDFTranscriptWriter {
    struct Entry {
        let title: String
        let subtitle: String
        let body: String
        let isFromMe: Bool
    }

    static func write(
        title: String,
        subtitle: String,
        entries: [Entry],
        to path: String,
        cancellationCheck: (() throws -> Void)? = nil
    ) throws {
        let outputURL = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: outputURL)

        guard let consumer = CGDataConsumer(url: outputURL as CFURL) else {
            throw NSError(domain: "Phosphor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF output file"])
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72 DPI
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "Phosphor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        let margin: CGFloat = 54
        let contentWidth = mediaBox.width - (margin * 2)
        let pageHeight = mediaBox.height
        let pageBottom = pageHeight - margin
        var y: CGFloat = margin
        var pageNumber = 0

        func beginPage() {
            context.beginPDFPage(nil)
            pageNumber += 1
            y = margin
        }

        func endPage() {
            let footer = attributed("Page \(pageNumber)", font: .systemFont(ofSize: 9), color: secondaryTextColor)
            draw(footer, in: CGRect(x: margin, y: pageHeight - margin + 18, width: contentWidth, height: 14), context: context, pageHeight: pageHeight)
            context.endPDFPage()
        }

        func ensureSpace(_ height: CGFloat) {
            if y + height > pageBottom {
                endPage()
                beginPage()
            }
        }

        func drawFlow(_ text: NSAttributedString, x: CGFloat, width: CGFloat, ruleColor: CGColor? = nil) throws {
            var offset = 0
            while offset < text.length {
                try cancellationCheck?()
                let available = pageBottom - y
                if available < 24 {
                    endPage()
                    beginPage()
                    continue
                }

                let remaining = text.attributedSubstring(from: NSRange(location: offset, length: text.length - offset))
                let height = min(measuredHeight(remaining, width: width), available)
                if let ruleColor {
                    context.setFillColor(ruleColor)
                    context.fill(CGRect(x: margin, y: pageHeight - y - height - 4, width: 3, height: height + 4))
                }

                let visible = draw(remaining, in: CGRect(x: x, y: y, width: width, height: height), context: context, pageHeight: pageHeight)
                y += height
                if visible <= 0 { break }
                offset += visible
                if offset < text.length {
                    endPage()
                    beginPage()
                }
            }
        }

        beginPage()

        let titleText = attributed(title, font: .systemFont(ofSize: 22, weight: .semibold), color: primaryTextColor)
        let titleHeight = measuredHeight(titleText, width: contentWidth)
        draw(titleText, in: CGRect(x: margin, y: y, width: contentWidth, height: titleHeight), context: context, pageHeight: pageHeight)
        y += titleHeight + 4

        let metaText = attributed(subtitle, font: .systemFont(ofSize: 10), color: secondaryTextColor)
        let metaHeight = measuredHeight(metaText, width: contentWidth)
        draw(metaText, in: CGRect(x: margin, y: y, width: contentWidth, height: metaHeight), context: context, pageHeight: pageHeight)
        y += metaHeight + 18

        for entry in entries {
            try cancellationCheck?()
            let header = attributed(entry.title, font: .systemFont(ofSize: 10, weight: .semibold), color: entry.isFromMe ? meAccentColor : secondaryTextColor)
            let body = attributed(entry.body.isEmpty ? "[Empty message]" : entry.body, font: .systemFont(ofSize: 11), color: primaryTextColor)
            let details = entry.subtitle.isEmpty ? nil : attributed(entry.subtitle, font: .systemFont(ofSize: 9), color: secondaryTextColor)

            let headerHeight = measuredHeight(header, width: contentWidth)
            let detailsHeight = details.map { measuredHeight($0, width: contentWidth - 12) } ?? 0

            ensureSpace(headerHeight + 20)

            draw(header, in: CGRect(x: margin, y: y, width: contentWidth, height: headerHeight), context: context, pageHeight: pageHeight)
            y += headerHeight + 4

            let ruleColor = entry.isFromMe ? meRuleColor : otherRuleColor
            try drawFlow(body, x: margin + 12, width: contentWidth - 12, ruleColor: ruleColor)
            y += 4

            if let details {
                ensureSpace(detailsHeight + 12)
                try drawFlow(details, x: margin + 12, width: contentWidth - 12)
            }
            y += 12
        }

        endPage()
        context.closePDF()
    }

    private static let primaryTextColor = NSColor(calibratedWhite: 0.08, alpha: 1)
    private static let secondaryTextColor = NSColor(calibratedWhite: 0.42, alpha: 1)
    private static let meAccentColor = NSColor(calibratedRed: 0.0, green: 0.36, blue: 0.88, alpha: 1)
    private static let meRuleColor = NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1).cgColor
    private static let otherRuleColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor

    private static func attributed(_ raw: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        return NSAttributedString(
            string: raw,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func measuredHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.length),
            nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        return max(ceil(size.height) + 2, 12)
    }

    @discardableResult
    private static func draw(_ text: NSAttributedString, in topLeftRect: CGRect, context: CGContext, pageHeight: CGFloat) -> Int {
        context.saveGState()
        let rect = CGRect(
            x: topLeftRect.origin.x,
            y: pageHeight - topLeftRect.origin.y - topLeftRect.height,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
        let path = CGPath(rect: rect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.length), path, nil)
        CTFrameDraw(frame, context)
        let visible = CTFrameGetVisibleStringRange(frame).length
        context.restoreGState()
        return visible
    }
}
