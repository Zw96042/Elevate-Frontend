import Foundation

/// Short-lived private previews; filenames are sanitized source titles and never contain session tokens.
enum DocumentPreviewFiles {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("ElevateDocumentPreviews", isDirectory: true)

    static func write(_ resource: SkywardBinaryHTTP.Resource, title: String = "Document") throws -> URL {
        try Task.checkCancellation()
        let suffix: String
        switch resource.mimeType {
        case "application/pdf": suffix = "pdf"
        case "image/jpeg": suffix = "jpg"
        case "image/png": suffix = "png"
        case "image/gif": suffix = "gif"
        default: throw SkywardError.invalidResponse("document format is unsupported")
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(filename(title: title, suffix: suffix))
        do {
            #if os(iOS)
            try resource.data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            #else
            try resource.data.write(to: file, options: .atomic)
            #endif
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var folder = directory
            try folder.setResourceValues(excluded)
            try Task.checkCancellation()
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func filename(title: String, suffix: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:?*\"<>|"))
        var name = String(title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined())
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if name.lowercased().hasSuffix("." + suffix) { name.removeLast(suffix.count + 1) }
        while name.utf8.count > 180 { name.removeLast() }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return (name.isEmpty ? "Document" : name) + "." + suffix
    }

    static func remove(_ file: URL) {
        let directory = file.deletingLastPathComponent()
        guard directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func clear() { try? FileManager.default.removeItem(at: root) }
}
