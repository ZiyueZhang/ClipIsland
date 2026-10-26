import AppKit
import Foundation

public enum ClipKind: String, Codable, CaseIterable {
    case text
    case link
    case file
    case image

    public var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .link: return "link"
        case .file: return "doc.badge.arrow.up"
        case .image: return "photo"
        }
    }

    public var label: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .file: return "文件"
        case .image: return "图片"
        }
    }
}

/// One clipboard-history entry.
public struct ClipItem: Identifiable, Equatable {
    public var id: Int64
    public let kind: ClipKind
    public let text: String?
    public let imagePath: String?
    public let imageSize: CGSize?
    public let sourceBundle: String?
    public let sourceName: String?
    public var createdAt: Date
    public var pinned: Bool
    public let contentHash: String

    public init(
        id: Int64,
        kind: ClipKind,
        text: String?,
        imagePath: String? = nil,
        imageSize: CGSize? = nil,
        sourceBundle: String? = nil,
        sourceName: String? = nil,
        createdAt: Date = Date(),
        pinned: Bool = false,
        contentHash: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.imageSize = imageSize
        self.sourceBundle = sourceBundle
        self.sourceName = sourceName
        self.createdAt = createdAt
        self.pinned = pinned
        self.contentHash = contentHash
    }

    public var displayText: String {
        switch kind {
        case .image:
            if let size = imageSize {
                return "图片 \(Int(size.width))×\(Int(size.height))"
            }
            return "图片"
        default:
            return (text ?? "").previewLine(limit: 200)
        }
    }

    /// Lazily-loaded thumbnail/full image for UI.
    public func loadImage() -> NSImage? {
        guard let imagePath else { return nil }
        return NSImage(contentsOfFile: imagePath)
    }
}

/// Payload captured from the pasteboard, before storage assigns identity.
public struct NewClip {
    public var kind: ClipKind
    public var text: String?
    public var imageData: Data? // PNG bytes; the store writes it to disk
    public var sourceBundle: String?
    public var sourceName: String?

    public init(kind: ClipKind, text: String? = nil, imageData: Data? = nil,
                sourceBundle: String? = nil, sourceName: String? = nil) {
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.sourceBundle = sourceBundle
        self.sourceName = sourceName
    }
}
