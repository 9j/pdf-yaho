import PDFKit
import PagecraftCore
import SwiftUI
import UniformTypeIdentifiers

final class PDFFile: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let pdf: PDFDocument

    init() {
        pdf = PDFDocument()
        pdf.insert(PDFOps.blankPage(), at: 0)
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let doc = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pdf = doc
    }

    func snapshot(contentType: UTType) throws -> Data {
        guard let data = pdf.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
