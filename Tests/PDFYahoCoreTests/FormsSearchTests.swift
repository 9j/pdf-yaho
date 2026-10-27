import PDFKit
import XCTest
@testable import PDFYahoCore

final class FormsSearchTests: XCTestCase {
    func testCreatedFieldsPersistAndReset() throws {
        let doc = PDFOpsTests().makeTextDocument(["form"])
        let page = try XCTUnwrap(doc.page(at: 0))
        let text = Forms.field(.text, in: CGRect(x: 72, y: 600, width: 200, height: 22), document: doc)
        page.addAnnotation(text)
        let box = Forms.field(.checkbox, in: CGRect(x: 72, y: 560, width: 16, height: 16), document: doc)
        page.addAnnotation(box)
        page.addAnnotation(Forms.field(.choice, in: CGRect(x: 72, y: 520, width: 120, height: 20), document: doc))
        XCTAssertEqual(Forms.field(.text, in: .zero, document: doc).fieldName, "Text 2")
        text.widgetStringValue = "Jane"
        box.buttonWidgetState = .onState
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(doc.write(to: url))
        let back = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let widgets = back.annotations.filter { $0.type == "Widget" }
        XCTAssertEqual(widgets.count, 3)
        XCTAssertEqual(widgets.first { $0.widgetFieldType == .text }?.widgetStringValue, "Jane")

        let previous = Forms.reset(doc)
        XCTAssertEqual(text.widgetStringValue, "")
        XCTAssertEqual(box.buttonWidgetState, .offState)
        previous.forEach { $0.restore() }
        XCTAssertEqual(text.widgetStringValue, "Jane")
    }

    func testWholeWordAndCaseSearch() {
        let doc = PDFOpsTests().makeTextDocument(["Cat category cat scatter CAT"])
        XCTAssertEqual(Search.find("cat", in: doc, matchCase: false, wholeWords: false).count, 5)
        XCTAssertEqual(Search.find("cat", in: doc, matchCase: false, wholeWords: true).count, 3)
        XCTAssertEqual(Search.find("cat", in: doc, matchCase: true, wholeWords: true).count, 1)
    }

    func testTextIndexMatchesWholeWordsAndBuildsSnippets() {
        let text = "Cat category cat scatter CAT" as NSString
        XCTAssertEqual(TextIndex.ranges(of: "cat", in: text, matchCase: false, wholeWords: false).count, 5)
        XCTAssertEqual(TextIndex.ranges(of: "cat", in: text, matchCase: false, wholeWords: true).map(\.location), [0, 13, 25])
        XCTAssertEqual(TextIndex.ranges(of: "café", in: "Le Cafe et le CAFÉ" as NSString, matchCase: false, wholeWords: true).count, 2)
        let snippet = TextIndex.snippet(for: NSRange(location: 13, length: 3), in: text)
        XCTAssertEqual(snippet.before + snippet.match + snippet.after, text as String)
        XCTAssertEqual(snippet.match, "cat")
    }

    func testIndexedSearchFindsPhrasesAcrossLines() async {
        let doc = PDFOpsTests().makeTextDocument(["first line ends\nwith a phrase", "second page phrase"])
        let index = TextIndex()
        await index.fill((0..<doc.pageCount).compactMap { doc.page(at: $0) })
        XCTAssertEqual(Search.find("phrase", in: doc, matchCase: true, wholeWords: true, index: index).count, 2)
        XCTAssertEqual(Search.find("ends with", in: doc, matchCase: true, wholeWords: false, index: index).count, 1)
    }

    func testRedactionMarksCoverMatches() {
        let doc = PDFOpsTests().makeTextDocument(["Secret 1234 and Secret 5678"])
        let marks = Search.redactionMarks(for: Search.find("Secret", in: doc, matchCase: true, wholeWords: true), style: .erase)
        XCTAssertEqual(marks.count, 2)
        XCTAssertTrue(marks.allSatisfy { Annotations.isRedaction($0.annotation) })
    }
}
