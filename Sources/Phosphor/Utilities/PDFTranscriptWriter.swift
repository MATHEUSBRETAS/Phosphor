import AppKit
import CoreText
import Foundation

/// Writes paginated, iMessage-inspired transcript PDFs without loading a WebView
/// or holding a giant rendered document in memory. Messages are drawn as rounded
/// chat bubbles: outgoing messages are right-aligned blue bubbles and incoming
/// messages are left-aligned light-gray bubbles.
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

        let margin: CGFloat = 42
        let contentWidth = mediaBox.width - (margin * 2)
        let pageHeight = mediaBox.height
        let pageBottom = pageHeight - margin
        let bubbleMaxWidth = contentWidth * 0.74
        let bubblePaddingX: CGFloat = 13
        let bubblePaddingY: CGFloat = 9
        let bubbleRadius: CGFloat = 17
        var y: CGFloat = margin
        var pageNumber = 0

        func beginPage() {
            context.beginPDFPage(nil)
            pageNumber += 1
            y = margin
            context.setFillColor(pageBackgroundColor)
            context.fill(mediaBox)
        }

        func endPage() {
            let footer = attributed("Page \(pageNumber)", font: .systemFont(ofSize: 9), color: secondaryTextColor, alignment: .center)
            draw(footer, in: CGRect(x: margin, y: pageHeight - margin + 18, width: contentWidth, height: 14), context: context, pageHeight: pageHeight)
            context.endPDFPage()
        }

        func ensureSpace(_ height: CGFloat) {
            if y + height > pageBottom {
                endPage()
                beginPage()
            }
        }

        func drawHeader() {
            let titleText = attributed(title, font: .systemFont(ofSize: 21, weight: .semibold), color: primaryTextColor, alignment: .center)
            let titleHeight = measuredHeight(titleText, width: contentWidth)
            draw(titleText, in: CGRect(x: margin, y: y, width: contentWidth, height: titleHeight), context: context, pageHeight: pageHeight)
            y += titleHeight + 4

            let metaText = attributed(subtitle, font: .systemFont(ofSize: 10), color: secondaryTextColor, alignment: .center)
            let metaHeight = measuredHeight(metaText, width: contentWidth)
            draw(metaText, in: CGRect(x: margin, y: y, width: contentWidth, height: metaHeight), context: context, pageHeight: pageHeight)
            y += metaHeight + 18
        }

        func drawRoundedBubble(x: CGFloat, topY: CGFloat, width: CGFloat, height: CGFloat, fill: CGColor) {
            let rect = CGRect(x: x, y: pageHeight - topY - height, width: width, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: bubbleRadius, cornerHeight: bubbleRadius, transform: nil)
            context.setFillColor(fill)
            context.addPath(path)
            context.fillPath()
        }

        func drawMessage(_ entry: Entry) throws {
            let bubbleFill = entry.isFromMe ? outgoingBubbleColor : incomingBubbleColor
            let textColor = entry.isFromMe ? outgoingTextColor : primaryTextColor
            let text = attributed(entry.body.isEmpty ? "[Empty message]" : entry.body,
                                  font: .systemFont(ofSize: 11.5),
                                  color: textColor)
            let meta = attributed(entry.subtitle,
                                  font: .systemFont(ofSize: 8.5),
                                  color: secondaryTextColor,
                                  alignment: .center)
            let sender = attributed(entry.title,
                                    font: .systemFont(ofSize: 9, weight: .medium),
                                    color: secondaryTextColor)

            let maxTextWidth = bubbleMaxWidth - (bubblePaddingX * 2)
            let preferredTextSize = measuredSize(text, width: maxTextWidth)
            let textWidth = min(maxTextWidth, max(80, ceil(preferredTextSize.width)))
            let metaHeight = entry.subtitle.isEmpty ? CGFloat(0) : measuredHeight(meta, width: contentWidth)
            ensureSpace(max(28, metaHeight + 24))

            if !entry.subtitle.isEmpty {
                draw(meta, in: CGRect(x: margin, y: y, width: contentWidth, height: metaHeight), context: context, pageHeight: pageHeight)
                y += metaHeight + 7
            }

            if !entry.isFromMe, !entry.title.isEmpty {
                let senderHeight = measuredHeight(sender, width: bubbleMaxWidth)
                ensureSpace(senderHeight + 18)
                draw(sender, in: CGRect(x: margin + 6, y: y, width: bubbleMaxWidth, height: senderHeight), context: context, pageHeight: pageHeight)
                y += senderHeight + 2
            }

            var offset = 0
            while offset < text.length {
                try cancellationCheck?()
                let remaining = text.attributedSubstring(from: NSRange(location: offset, length: text.length - offset))
                let remainingHeight = measuredHeight(remaining, width: textWidth)

                var availableTextHeight = pageBottom - y - (bubblePaddingY * 2)
                if availableTextHeight < 24 {
                    endPage()
                    beginPage()
                    availableTextHeight = pageBottom - y - (bubblePaddingY * 2)
                }

                let segmentTextHeight = min(remainingHeight, availableTextHeight)
                let bubbleHeight = segmentTextHeight + (bubblePaddingY * 2)
                let bubbleWidth = textWidth + (bubblePaddingX * 2)
                let bubbleX = entry.isFromMe ? margin + contentWidth - bubbleWidth : margin

                drawRoundedBubble(x: bubbleX, topY: y, width: bubbleWidth, height: bubbleHeight, fill: bubbleFill)
                let visible = draw(
                    remaining,
                    in: CGRect(
                        x: bubbleX + bubblePaddingX,
                        y: y + bubblePaddingY,
                        width: textWidth,
                        height: segmentTextHeight
                    ),
                    context: context,
                    pageHeight: pageHeight
                )

                y += bubbleHeight + 8
                if visible <= 0 { break }
                offset += visible
                if offset < text.length {
                    endPage()
                    beginPage()
                }
            }
        }

        beginPage()
        drawHeader()

        for entry in entries {
            try cancellationCheck?()
            try drawMessage(entry)
        }

        endPage()
        context.closePDF()
    }

    private static let pageBackgroundColor = NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.976, alpha: 1).cgColor
    private static let primaryTextColor = NSColor(calibratedWhite: 0.08, alpha: 1)
    private static let secondaryTextColor = NSColor(calibratedWhite: 0.48, alpha: 1)
    private static let outgoingTextColor = NSColor.white
    private static let outgoingBubbleColor = NSColor(calibratedRed: 0.00, green: 0.478, blue: 1.00, alpha: 1).cgColor
    private static let incomingBubbleColor = NSColor(calibratedRed: 0.898, green: 0.898, blue: 0.918, alpha: 1).cgColor

    private static func attributed(_ raw: String,
                                   font: NSFont,
                                   color: NSColor,
                                   alignment: NSTextAlignment = .left) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        paragraph.alignment = alignment
        return NSAttributedString(
            string: raw,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func measuredSize(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: text.length),
            nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        return CGSize(width: ceil(size.width), height: ceil(size.height) + 2)
    }

    private static func measuredHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        max(measuredSize(text, width: width).height, 12)
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
