import Foundation

public enum PageText {
    /// Selected page text as it reads. Some PDFs put a word joiner (U+2060) after every Korean syllable and PDFKit
    /// reports a space after each one, so "재정지침" would copy as "재 정 지 침". Real spaces carry no joiner.
    public static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2060} ", with: "").replacingOccurrences(of: "\u{2060}", with: "")
    }
}
