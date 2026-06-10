import Foundation
import UIKit

/// 生成したグッズ画像をアプリ内のDocumentsフォルダへ保存します。
enum ImageStore {
    static let goodsFolderName = "GoodsImages"
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    static func save(_ image: UIImage, id: UUID = UUID()) throws -> String {
        let folderURL = try goodsFolderURL()
        let fileURL = folderURL.appendingPathComponent("\(id.uuidString).png")
        let normalizedImage = image.normalizedForRendering()

        guard let data = normalizedImage.pngData() else {
            throw ImageStoreError.cannotCreatePNG
        }

        try data.write(to: fileURL, options: [.atomic])
        imageCache.setObject(normalizedImage, forKey: fileURL.lastPathComponent as NSString)
        return fileURL.lastPathComponent
    }

    static func save(_ data: Data, path: String) throws {
        let folderURL = try goodsFolderURL()
        let fileURL = folderURL.appendingPathComponent(path)
        try data.write(to: fileURL, options: [.atomic])

        if let cachedImage = UIImage(data: data) {
            imageCache.setObject(cachedImage.normalizedForRendering(), forKey: path as NSString)
        }
    }

    static func load(path: String) -> UIImage? {
        if let cachedImage = imageCache.object(forKey: path as NSString) {
            return cachedImage
        }

        guard let fileURL = resolvedFileURL(for: path) else {
            return nil
        }

        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }

        imageCache.setObject(image, forKey: path as NSString)
        return image
    }

    static func url(for path: String) -> URL? {
        resolvedFileURL(for: path)
    }

    static func delete(path: String) {
        imageCache.removeObject(forKey: path as NSString)

        guard let fileURL = resolvedFileURL(for: path) else {
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func goodsFolderURL() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folderURL = documentsURL.appendingPathComponent(goodsFolderName, isDirectory: true)

        if FileManager.default.fileExists(atPath: folderURL.path) == false {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        return folderURL
    }

    static func resolvedPath(for path: String) -> String? {
        resolvedFileURL(for: path)?.lastPathComponent
    }

    static func resolvedFileURL(for path: String, in folderURL: URL) -> URL? {
        let primaryURL = folderURL.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let baseName = (path as NSString).deletingPathExtension
        let preferredExtensions = ["png", "jpg", "jpeg", "heic"]

        for fileExtension in preferredExtensions {
            let candidateURL = folderURL.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    private static func resolvedFileURL(for path: String) -> URL? {
        guard let folderURL = try? goodsFolderURL() else {
            return nil
        }

        return resolvedFileURL(for: path, in: folderURL)
    }
}

enum ImageStoreError: Error {
    case cannotCreatePNG
}
