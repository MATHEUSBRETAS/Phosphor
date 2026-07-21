import Foundation

/// Represents an iOS photo album parsed from Photos.sqlite in an iOS backup.
struct PhotoAlbum: Identifiable, Hashable {
    let id: Int       // Z_PK from ZGENERICALBUM
    let title: String // ZTITLE
    let kind: Kind
    let items: [MediaItem]

    enum Kind {
        case regular
        case smart

        var sfSymbol: String {
            switch self {
            case .regular: return "rectangle.stack"
            case .smart: return "wand.and.stars"
            }
        }

        var label: String {
            switch self {
            case .regular: return "Album"
            case .smart: return "Smart Album"
            }
        }
    }

    var itemCount: Int { items.count }

    /// First item, usable as a representative thumbnail.
    var thumbnailItem: MediaItem? { items.first }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PhotoAlbum, rhs: PhotoAlbum) -> Bool { lhs.id == rhs.id }
}
