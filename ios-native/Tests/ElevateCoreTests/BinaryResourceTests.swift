import Foundation
import Testing
@testable import ElevateCore

@Suite("Private binary resources")
struct BinaryResourceTests {
    @Test func sameOriginLocationsOnly() throws {
        let base = "https://example.edu/web/"
        #expect(try SkywardBinaryHTTP.resourceURL(relativePath: "qdirconfig1.p?StuPic=1", baseUrl: base).host == "example.edu")
        for path in ["https://evil.edu/photo.png", "//evil.edu/photo.png", "http://example.edu/photo.png", "https://user:pass@example.edu/a", "https://example.edu:444/a", "photo.png#fragment"] {
            #expect(throws: (any Error).self) { try SkywardBinaryHTTP.resourceURL(relativePath: path, baseUrl: base) }
        }
    }

    @Test func loginRedirectsAreExpiryEvenBeforeBodyParsing() throws {
        for path in ["fwemnu01.w", "SkyPortLogin.w"] {
            #expect(throws: (any Error).self) { try SkywardHTTP.checkSessionRedirect(URL(string: "https://example.edu/web/" + path)) }
        }
        try SkywardHTTP.checkSessionRedirect(URL(string: "https://example.edu/web/qdirconfig1.p?file=fwemnu01.w"))
    }

    @Test func contentMustMatchDeclaredFormat() throws {
        try SkywardBinaryHTTP.validateContent(Data("%PDF-1.7\n".utf8), mimeType: "application/pdf")
        try SkywardBinaryHTTP.validateContent(Data([137, 80, 78, 71, 13, 10, 26, 10]), mimeType: "image/png")
        try SkywardBinaryHTTP.validateContent(Data([255, 216, 255, 224]), mimeType: "image/jpeg")
        for mime in ["application/pdf", "image/png", "image/jpeg", "image/gif", "image/heic"] {
            #expect(throws: (any Error).self) { try SkywardBinaryHTTP.validateContent(Data("<html>Login</html>".utf8), mimeType: mime) }
            #expect(throws: (any Error).self) { try SkywardBinaryHTTP.validateContent(Data(), mimeType: mime) }
        }
    }

    @Test func exportedNamesRetainTitlesAndCannotTraverseDirectories() {
        #expect(DocumentPreviewFiles.filename(title: "Quarter 1 report card", suffix: "pdf") == "Quarter 1 report card.pdf")
        #expect(DocumentPreviewFiles.filename(title: "../../Report/2026.pdf", suffix: "pdf") == "Report 2026.pdf")
        #expect(DocumentPreviewFiles.filename(title: " ... ", suffix: "pdf") == "Document.pdf")
        #expect(DocumentPreviewFiles.filename(title: String(repeating: "報", count: 200), suffix: "pdf").utf8.count <= 184)
    }

    @Test func previewIsPrivateAndRemovedWithoutDeletingUnrelatedFiles() throws {
        let resource = SkywardBinaryHTTP.Resource(data: Data("%PDF-1.7\n".utf8), mimeType: "application/pdf")
        let file = try DocumentPreviewFiles.write(resource)
        #expect(file.lastPathComponent == "Document.pdf")
        #expect(try Data(contentsOf: file) == resource.data)
        #expect(try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let unrelated = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("unrelated".utf8).write(to: unrelated)
        defer { try? FileManager.default.removeItem(at: unrelated) }
        DocumentPreviewFiles.remove(unrelated)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        DocumentPreviewFiles.remove(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
