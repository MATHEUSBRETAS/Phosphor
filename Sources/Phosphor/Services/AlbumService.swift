import Foundation

/// Parses iOS Photos.sqlite to extract album structure from an iOS backup.
///
/// iOS stores photo metadata in CameraRollDomain/Media/PhotoData/Photos.sqlite.
/// Albums live in ZGENERICALBUM; assets in ZASSET; membership in a dynamically-named
/// junction table (Z_{n}ASSETS) whose columns are detected at runtime from the schema.
@MainActor
final class AlbumService: ObservableObject {

    @Published var albums: [PhotoAlbum] = []
    @Published var isLoading = false
    @Published var lastError: String?

    /// Load albums from the backup, correlating Photos.sqlite assets with
    /// already-loaded MediaItems from Manifest.db.
    /// Returns silently (no albums, no error) when Photos.sqlite is absent.
    func loadAlbums(from backupPath: String, allItems: [MediaItem]) async {
        guard !allItems.isEmpty else { return }
        isLoading = true
        lastError = nil

        do {
            let manifest = try BackupManifest(backupPath: backupPath)
            guard let entry = try manifest.photosDatabase() else {
                albums = []
                isLoading = false
                return
            }
            let diskPath = entry.diskPath(backupRoot: backupPath)
            albums = try Self.parseAlbums(dbPath: diskPath, allItems: allItems)
        } catch {
            lastError = error.localizedDescription
            albums = []
        }

        isLoading = false
    }

    /// Extract all items in an album to a destination folder.
    func extractAlbum(
        _ album: PhotoAlbum,
        from backupPath: String,
        to destination: String
    ) async -> Int {
        do {
            let manifest = try BackupManifest(backupPath: backupPath)
            let fm = FileManager.default
            try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
            var extracted = 0
            for item in album.items {
                let entry = BackupManifest.FileEntry(
                    id: item.id,
                    domain: item.domain,
                    relativePath: item.relativePath,
                    flags: 1,
                    size: item.size
                )
                let dest = (destination as NSString).appendingPathComponent(item.filename)
                do {
                    try manifest.extractFile(entry, to: dest)
                    extracted += 1
                } catch {}
            }
            return extracted
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    // MARK: - Private

    private struct JunctionInfo {
        let tableName: String
        let albumColumn: String // ends with "ALBUMS" -> FK to ZGENERICALBUM.Z_PK
        let assetColumn: String // ends with "ASSETS" -> FK to ZASSET.Z_PK
    }

    private static func parseAlbums(dbPath: String, allItems: [MediaItem]) throws -> [PhotoAlbum] {
        let db = try SQLiteReader(path: dbPath)

        // Build fast lookups: key is lowercased so matching is case-insensitive.
        // Full relative-path match is precise; filename is a lenient fallback.
        var byPath: [String: MediaItem] = [:]
        var byFilename: [String: MediaItem] = [:]
        for item in allItems {
            byPath[item.relativePath.lowercased()] = item
            if byFilename[item.filename.lowercased()] == nil {
                byFilename[item.filename.lowercased()] = item
            }
        }

        guard let junction = try findJunctionTable(in: db) else { return [] }

        let albumRows = try db.query(
            "SELECT Z_PK, ZTITLE, ZKIND FROM ZGENERICALBUM WHERE ZTITLE IS NOT NULL AND ZTITLE != '' ORDER BY ZTITLE"
        )

        var result: [PhotoAlbum] = []
        for albumRow in albumRows {
            guard let pk = albumRow["Z_PK"] as? Int,
                  let title = albumRow["ZTITLE"] as? String else { continue }
            let kindInt = (albumRow["ZKIND"] as? Int) ?? 2
            // ZKIND >= 1500 are system/smart albums (Recents, Favorites, etc.)
            let kind: PhotoAlbum.Kind = kindInt >= 1500 ? .smart : .regular

            // PK is an Int from the DB; interpolate directly to avoid string-binding
            // type-mismatch issues with SQLite affinity rules.
            let sql = """
                SELECT a.ZDIRECTORY, a.ZFILENAME
                FROM ZASSET a
                JOIN \(junction.tableName) j ON a.Z_PK = j.\(junction.assetColumn)
                WHERE j.\(junction.albumColumn) = \(pk)
                ORDER BY a.ZDATECREATED
                """
            let assetRows = (try? db.query(sql)) ?? []

            var albumItems: [MediaItem] = []
            for assetRow in assetRows {
                guard let filename = assetRow["ZFILENAME"] as? String else { continue }
                // Try precise path match (Media/DCIM/<dir>/<filename>)
                if let dir = assetRow["ZDIRECTORY"] as? String,
                   let item = byPath["media/dcim/\(dir.lowercased())/\(filename.lowercased())"] {
                    albumItems.append(item)
                } else if let item = byFilename[filename.lowercased()] {
                    albumItems.append(item)
                }
            }

            guard !albumItems.isEmpty else { continue }
            result.append(PhotoAlbum(id: pk, title: title, kind: kind, items: albumItems))
        }

        return result
    }

    /// Detect the dynamic album-asset junction table by inspecting sqlite_master.
    /// iOS generates a table named Z_{n}ASSETS with columns Z_{n}ALBUMS and Z_{m}ASSETS.
    private static func findJunctionTable(in db: SQLiteReader) throws -> JunctionInfo? {
        let tableRows = try db.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z_%ASSETS' AND name NOT LIKE 'Z_META%'"
        )
        for tableRow in tableRows {
            guard let name = tableRow["name"] as? String else { continue }
            let colNames = (try? db.columns(for: name))?.map { $0.name } ?? []
            guard let albumCol = colNames.first(where: { $0.hasSuffix("ALBUMS") }),
                  let assetCol = colNames.first(where: { $0.hasSuffix("ASSETS") }) else { continue }
            return JunctionInfo(tableName: name, albumColumn: albumCol, assetColumn: assetCol)
        }
        return nil
    }
}
