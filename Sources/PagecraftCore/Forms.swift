import AppKit
import PDFKit

/// Creating and resetting AcroForm fields.
public enum Forms {
    public enum FieldKind: String, CaseIterable, Identifiable, Sendable {
        case text = "Text Field", checkbox = "Checkbox", radio = "Radio Button", choice = "Drop-down"
        public var id: String { rawValue }
    }

    /// A new form field in `rect`, named uniquely within `doc`.
    public static func field(_ kind: FieldKind, in rect: CGRect, document doc: PDFDocument) -> PDFAnnotation {
        let existing = Set(PDFOps.pages(of: doc).flatMap(\.annotations).compactMap(\.fieldName))
        let base = kind == .text ? "Text" : kind == .checkbox ? "Check" : kind == .radio ? "Choice" : "Dropdown"
        var n = 1
        while existing.contains("\(base) \(n)") && kind != .radio { n += 1 }
        let w = PDFAnnotation(bounds: rect, forType: .widget, withProperties: nil)
        w.backgroundColor = NSColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 0.5)
        let border = PDFBorder()
        border.lineWidth = 1
        w.border = border
        w.color = NSColor(srgbRed: 0.3, green: 0.45, blue: 0.8, alpha: 1)
        switch kind {
        case .text:
            w.widgetFieldType = .text
            w.font = NSFont.systemFont(ofSize: min(12, max(8, rect.height * 0.6)))
            w.fontColor = .black
            w.widgetStringValue = ""
        case .checkbox:
            w.widgetFieldType = .button
            w.widgetControlType = .checkBoxControl
            w.buttonWidgetState = .offState
        case .radio:
            w.widgetFieldType = .button
            w.widgetControlType = .radioButtonControl
            w.buttonWidgetStateString = "Option \(n)"
            w.buttonWidgetState = .offState
        case .choice:
            w.widgetFieldType = .choice
            w.isListChoice = false
            w.choices = ["Option 1", "Option 2", "Option 3"]
            w.font = NSFont.systemFont(ofSize: 11)
            w.widgetStringValue = "Option 1"
        }
        // Set last: assigning the field type resets the name to a generated one.
        w.fieldName = kind == .radio ? "\(base) Group" : "\(base) \(n)"
        return w
    }

    public struct FieldValue {
        let annotation: PDFAnnotation
        let string: String?
        let state: PDFWidgetCellState

        public func restore() {
            annotation.widgetStringValue = string
            annotation.buttonWidgetState = state
        }
    }

    /// Clears every filled field and returns the previous values so the reset can be undone.
    @discardableResult
    public static func reset(_ doc: PDFDocument) -> [FieldValue] {
        var previous: [FieldValue] = []
        for page in PDFOps.pages(of: doc) {
            for w in page.annotations where w.type == "Widget" {
                previous.append(FieldValue(annotation: w, string: w.widgetStringValue, state: w.buttonWidgetState))
                switch w.widgetFieldType {
                case .button: w.buttonWidgetState = .offState
                case .text: w.widgetStringValue = ""
                case .choice: w.widgetStringValue = w.choices?.first ?? ""
                default: break
                }
            }
        }
        return previous
    }
}

extension Annotations {
    public enum RedactionStyle: String, CaseIterable, Identifiable, Sendable {
        case blackout = "Black Box", erase = "White Out"
        public var id: String { rawValue }
    }

    public static func redaction(bounds: CGRect, style: RedactionStyle) -> PDFAnnotation {
        let a = redaction(bounds: bounds)
        if style == .erase {
            a.color = .white
            a.interiorColor = .white
        }
        return a
    }
}

public enum Search {
    /// Matches of `query` in `doc`, optionally case sensitive and limited to whole words.
    public static func find(_ query: String, in doc: PDFDocument, matchCase: Bool, wholeWords: Bool) -> [PDFSelection] {
        let options: NSString.CompareOptions = matchCase ? [] : [.caseInsensitive, .diacriticInsensitive]
        let results = doc.findString(query, withOptions: options)
        guard wholeWords else { return results }
        return results.filter { isWholeWord($0) }
    }

    static func isWholeWord(_ selection: PDFSelection) -> Bool {
        guard let match = selection.string, let extended = selection.copy() as? PDFSelection else { return true }
        extended.extend(atStart: 1)
        extended.extend(atEnd: 1)
        let text = extended.string ?? match
        guard let range = text.range(of: match) else { return true }
        let before = text[..<range.lowerBound].last
        let after = text[range.upperBound...].first
        func isWordChar(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
        return !isWordChar(before) && !isWordChar(after)
    }

    /// Redaction marks over every match, one per line of each match.
    public static func redactionMarks(for results: [PDFSelection], style: Annotations.RedactionStyle) -> [(page: PDFPage, annotation: PDFAnnotation)] {
        results.flatMap { result in
            result.selectionsByLine().flatMap { line in
                line.pages.map { page in (page, Annotations.redaction(bounds: line.bounds(for: page).insetBy(dx: -1, dy: -1), style: style)) }
            }
        }
    }
}
