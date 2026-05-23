import Foundation
import GrokClient

extension GrokCLI {
    struct InteractiveVideoReferenceInput {
        let prompt: String
        let referenceImages: [XAIVideoReferenceImage]
        let fileNames: [String]
    }

    static func interactiveVideoReferenceInput(from input: String, requiresPrompt: Bool = true) throws -> InteractiveVideoReferenceInput? {
        let args: [String]
        do {
            args = try splitCommandArguments(input)
        } catch {
            return nil
        }

        var promptArgs: [String] = []
        var references: [XAIVideoReferenceImage] = []
        var fileNames: [String] = []

        for arg in args {
            if let reference = try videoReferenceImage(from: arg) {
                references.append(reference.image)
                fileNames.append(reference.fileName)
            } else {
                promptArgs.append(arg)
            }
        }

        guard !references.isEmpty else {
            return nil
        }
        guard references.count <= 7 else {
            throw GrokError.apiError("xAI reference-to-video supports at most 7 reference images")
        }

        let prompt = promptArgs.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requiresPrompt || !prompt.isEmpty else {
            throw GrokError.apiError("Reference-to-video requires a prompt with the dropped image path")
        }

        return InteractiveVideoReferenceInput(prompt: prompt, referenceImages: references, fileNames: fileNames)
    }

    private static func videoReferenceImage(from rawPath: String) throws -> (image: XAIVideoReferenceImage, fileName: String)? {
        guard let fileURL = referenceImageFileURL(from: rawPath) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw GrokError.apiError("Could not read reference image \(fileURL.path): \(error.localizedDescription)")
        }

        let mimeType = imageMIMEType(for: fileURL)
        let dataURI = "data:\(mimeType);base64,\(data.base64EncodedString())"
        return (XAIVideoReferenceImage(url: dataURI), fileURL.lastPathComponent)
    }

    private static func referenceImageFileURL(from rawPath: String) -> URL? {
        guard isPathLike(rawPath) else {
            return nil
        }

        let fileURL: URL
        if rawPath.lowercased().hasPrefix("file://"), let url = URL(string: rawPath), url.isFileURL {
            fileURL = url
        } else {
            fileURL = URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
        }

        guard supportedReferenceImageExtensions.contains(fileURL.pathExtension.lowercased()) else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard !isDirectory.boolValue else {
            return nil
        }
        return fileURL
    }

    private static func isPathLike(_ value: String) -> Bool {
        value.hasPrefix("/") ||
            value.hasPrefix("./") ||
            value.hasPrefix("../") ||
            value.hasPrefix("~/") ||
            value.lowercased().hasPrefix("file://")
    }

    private static let supportedReferenceImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "heic", "heif"
    ]

    private static func imageMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        default:
            return "application/octet-stream"
        }
    }
}
