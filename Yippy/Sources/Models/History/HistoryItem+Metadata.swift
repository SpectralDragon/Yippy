import Foundation
import Cocoa

extension HistoryItem.Metadata {

    private static let colorPasteboardTypeIdentifiers: Set<String> = [
        "com.apple.cocoa.pasteboard.color"
    ]

    private static let imagePasteboardTypeIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.tiff.rawValue,
        "public.jpeg",
        "public.png",
        "public.heic",
        "public.heif",
        "public.gif",
        "public.bmp",
        "public.webp"
    ]

    private static let moviePasteboardTypeIdentifiers: Set<String> = [
        "public.movie",
        "public.audiovisual-content"
    ]

    private static let stringPasteboardTypeIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.string.rawValue,
        "public.utf8-plain-text",
        "public.utf16-external-plain-text",
        "public.utf16-internal-plain-text"
    ]

    private static let richTextPasteboardTypeIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.rtfd.rawValue,
        "com.apple.flat-rtfd"
    ]

    private static let htmlPasteboardTypeIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.html.rawValue
    ]

    private static let urlPasteboardTypeIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.URL.rawValue
    ]

    private static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "heif", "svg", "webp"
    ]

    private static let videoFileExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "hevc"
    ]

    private static let knownCodeBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.jetbrains.AppCode",
        "com.sublimetext.4",
        "com.github.atom",
        "com.google.android.studio",
        "org.gnu.emacs",
        "com.apple.dt.playground",
        "com.github.VSCodium"
    ]

    private static let knownBundleDisplayNames: [String: String] = [
        "com.microsoft.VSCode": "VS Code",
        "com.apple.dt.Xcode": "Xcode",
        "com.jetbrains.AppCode": "AppCode",
        "com.sublimetext.4": "Sublime Text",
        "com.github.atom": "Atom",
        "com.google.android.studio": "Android Studio",
        "org.gnu.emacs": "Emacs",
        "com.apple.dt.playground": "Playgrounds",
        "com.github.VSCodium": "VSCodium"
    ]

    static func infer(
        types: [NSPasteboard.PasteboardType],
        dataProvider: (NSPasteboard.PasteboardType) -> Data?,
        originBundleId: String?
    ) -> HistoryItem.Metadata {
        let category = determineCategory(types: types, dataProvider: dataProvider, originBundleId: originBundleId)
        let applicationName = originBundleId.flatMap { resolveApplicationName(for: $0) }
        return HistoryItem.Metadata(category: category, originBundleId: originBundleId, originApplicationName: applicationName)
    }

    private static func determineCategory(
        types: [NSPasteboard.PasteboardType],
        dataProvider: (NSPasteboard.PasteboardType) -> Data?,
        originBundleId: String?
    ) -> HistoryItem.Metadata.Category {
        let identifiers = Set(types.map { $0.rawValue })

        if identifiers.intersection(colorPasteboardTypeIdentifiers).isEmpty == false {
            return .color
        }

        if identifiers.intersection(imagePasteboardTypeIdentifiers).isEmpty == false {
            return .photo
        }

        if identifiers.intersection(moviePasteboardTypeIdentifiers).isEmpty == false {
            return .video
        }

        if identifiers.contains(NSPasteboard.PasteboardType.pdf.rawValue) {
            return .file
        }

        if let fileURLType = types.first(where: { $0 == .fileURL }),
           let data = dataProvider(fileURLType),
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            let ext = url.pathExtension.lowercased()
            if imageFileExtensions.contains(ext) {
                return .photo
            }
            if videoFileExtensions.contains(ext) {
                return .video
            }
            if url.isFileURL {
                return .file
            }
        }

        if let urlType = types.first(where: { urlPasteboardTypeIdentifiers.contains($0.rawValue) }),
           let data = dataProvider(urlType),
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.scheme != nil {
            return .url
        }

        if let text = extractPlainText(types: types, dataProvider: dataProvider) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .text
            }

            if isColorString(trimmed) {
                return .color
            }

            if isURLString(trimmed) {
                return .url
            }

            return categoryForText(trimmed, originBundleId: originBundleId)
        }

        return .other
    }

    private static func extractPlainText(
        types: [NSPasteboard.PasteboardType],
        dataProvider: (NSPasteboard.PasteboardType) -> Data?
    ) -> String? {
        if let stringType = types.first(where: { stringPasteboardTypeIdentifiers.contains($0.rawValue) }),
           let data = dataProvider(stringType),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        if let richTextType = types.first(where: { richTextPasteboardTypeIdentifiers.contains($0.rawValue) }),
           let data = dataProvider(richTextType),
           let attributedString = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributedString.string
        }

        if let htmlType = types.first(where: { htmlPasteboardTypeIdentifiers.contains($0.rawValue) }),
           let data = dataProvider(htmlType),
           let attributedString = NSAttributedString(
                html: data,
                options: [
                    .characterEncoding: String.Encoding.utf8.rawValue,
                    .documentType: NSAttributedString.DocumentType.html
                ],
                documentAttributes: nil
           ) {
            return attributedString.string
        }

        return nil
    }

    private static func categoryForText(_ text: String, originBundleId: String?) -> HistoryItem.Metadata.Category {
        if let originBundleId = originBundleId, knownCodeBundleIdentifiers.contains(originBundleId) {
            return .code
        }

        if looksLikeCode(text) {
            return .code
        }

        return .text
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let indicators = [
            "{", "}", "[", "]", "=>", "->", "::", "&&", "||", "!=", "==",
            "func ", "class ", "struct ", "enum ", "public ", "private ", "let ", "var ",
            "const ", "import ", "#include", "#define", "template ", "switch ", "case ",
            "if ", "else", "for ", "while ", "return ", "async ", "await ", "def ", "lambda"
        ]
        let indicatorMatches = indicators.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        if indicatorMatches >= 2 {
            return true
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyLines.count >= 3 {
            let indentedLines = nonEmptyLines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
            let bracketCount = text.reduce(0) { "{}[]();".contains($1) ? $0 + 1 : $0 }
            if indentedLines.count >= 1 && bracketCount >= 2 {
                return true
            }
            if bracketCount >= 6 {
                return true
            }
        }

        return false
    }

    private static func isURLString(_ string: String) -> Bool {
        if string.contains(" ") { return false }
        if let url = URL(string: string), url.scheme != nil {
            if url.host != nil || url.scheme == "file" {
                return true
            }
        }
        return false
    }

    private static func isColorString(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hex = trimmed.dropFirst()
            return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy { $0.isHexDigit }
        }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("rgb(") || lowercased.hasPrefix("rgba(") {
            return true
        }
        if lowercased.hasPrefix("hsl(") || lowercased.hasPrefix("hsla(") {
            return true
        }
        return false
    }

    private static func resolveApplicationName(for bundleId: String) -> String? {
        if let known = knownBundleDisplayNames[bundleId] {
            return known
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            if let bundle = Bundle(url: url) {
                if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                    return displayName
                }
                if let name = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String {
                    return name
                }
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return nil
    }
}
