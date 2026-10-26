import PDFKit
import PagecraftCore
import SwiftUI
import UniformTypeIdentifiers

final class PDFFile: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let pdf: PDFDocument
    /// Password needed to open the file. Kept after unlocking so saving preserves the protection.
    var userPassword: String?
    /// Password that guards permissions; defaults to the open password.
    var ownerPassword: String?

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
        let options = PDFOps.WriteOptions(userPassword: userPassword, ownerPassword: ownerPassword)
        guard let data = PDFOps.data(pdf, options: options) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
