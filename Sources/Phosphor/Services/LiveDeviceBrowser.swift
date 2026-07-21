import Foundation

/// Browse device content LIVE without needing a backup.
/// Primary: pymobiledevice3 AFC (no FUSE needed). Fallback: ifuse.
@MainActor
final class LiveDeviceBrowser: ObservableObject {

    @Published var photos: [LivePhoto] = []
    @Published var albums: [LiveAlbum] = []
    @Published var isLoading = false
    @Published var albumsLoading = false
    @Published var isMounted = false
    @Published var lastError: String?
    @Published var mountPath: String?
    @Published var photoCount: Int = 0

    private var deviceUDID: String?
    private var usesAFC = false
    private var cachedDCIMFolders: [String] = []

    struct LiveAlbum: Identifiable, Hashable {
        let id: Int
        let title: String
        let kind: PhotoAlbum.Kind
        let photos: [LivePhoto]

        var photoCount: Int { photos.count }
        var thumbnailPhoto: LivePhoto? { photos.first }

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: LiveAlbum, rhs: LiveAlbum) -> Bool { lhs.id == rhs.id }
    }

    struct LivePhoto: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        let size: UInt64
        let modified: Date?
        let isVideo: Bool

        var sizeString: String { size.formattedFileSize }

        var sfSymbol: String {
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "mov", "mp4", "m4v": return "video.fill"
            case "png": return "photo"
            default: return "photo"
            }
        }

        var isScreenshot: Bool {
            name.lowercased().contains("screenshot") || name.hasPrefix("IMG_") && name.contains("PNG")
        }
    }

    // MARK: - Connect

    /// Connect to device via pymobiledevice3 AFC (primary) or ifuse (fallback).
    func mount(udid: String) async -> Bool {
        deviceUDID = udid

        // Primary: pymobiledevice3 AFC - scan DCIM structure first
        if PyMobileDevice.available() {
            // List DCIM subfolders to count photos before downloading
            let dcimContents = await PyMobileDevice.afcList(path: "/DCIM", udid: udid)
            if !dcimContents.isEmpty {
                usesAFC = true
                isMounted = true

                cachedDCIMFolders = dcimContents
                    .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
                    .sorted()
                photoCount = 0
                return true
            }
        }

        guard Shell.which("ifuse") != nil else {
            lastError = "Could not access device photos. Install or repair pymobiledevice3 with: pipx install pymobiledevice3"
            return false
        }

        // Optional legacy fallback: ifuse mount
        let tmpDir = NSTemporaryDirectory() + "phosphor-live-\(udid.prefix(8))"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let ifuseResult = await Shell.runAsync("ifuse", arguments: ["-u", udid, tmpDir])
        if ifuseResult.succeeded {
            mountPath = tmpDir
            usesAFC = false
            isMounted = true
            return true
        }

        lastError = "Could not access device. Install pymobiledevice3: pipx install pymobiledevice3"
        return false
    }

    func unmount() async {
        if let mount = mountPath, !usesAFC {
            let _ = await Shell.runAsync("umount", arguments: [mount])
            try? FileManager.default.removeItem(atPath: mount)
        }
        mountPath = nil
        deviceUDID = nil
        isMounted = false
        usesAFC = false
        cachedDCIMFolders = []
        photos = []
        photoCount = 0
    }

    // MARK: - Photo Scanning

    /// Scan and selectively pull photos from device.
    func scanPhotos() async {
        isLoading = true
        photos = []

        if usesAFC {
            await scanPhotosViaAFC()
        } else {
            await scanPhotosViaMount()
        }

        isLoading = false
    }

    /// Scan photos via pymobiledevice3 AFC - list only, no download until export.
    private func scanPhotosViaAFC() async {
        guard let udid = deviceUDID else { return }

        let photoExtensions = Set(["jpg", "jpeg", "heic", "heif", "png", "gif", "webp",
                                    "mov", "mp4", "m4v", "3gp"])

        let dcimContents = cachedDCIMFolders.isEmpty
            ? await PyMobileDevice.afcList(path: "/DCIM", udid: udid).sorted()
            : cachedDCIMFolders
        var found: [LivePhoto] = []

        for subfolder in dcimContents {
            guard !subfolder.isEmpty else { continue }

            // Just list files - don't download them yet
            let files = await PyMobileDevice.afcList(path: "/DCIM/\(subfolder)", udid: udid)

            for file in files {
                let ext = (file as NSString).pathExtension.lowercased()
                guard photoExtensions.contains(ext) else { continue }

                let remotePath = "/DCIM/\(subfolder)/\(file)"
                let isVideo = ["mov", "mp4", "m4v", "3gp"].contains(ext)

                found.append(LivePhoto(
                    id: remotePath, name: file, path: remotePath,
                    size: 0, modified: nil, isVideo: isVideo
                ))
            }
        }

        photos = found
        photoCount = found.count
    }

    /// Pull a single photo from device to local temp for viewing/export.
    /// Returns (localPath, errorMessage) — exactly one will be non-nil.
    func pullPhoto(_ photo: LivePhoto, timeout: TimeInterval = 60) async -> (path: String?, error: String?) {
        guard let udid = deviceUDID else {
            return (nil, "Device disconnected. Reconnect and try again.")
        }
        let tmpDir = NSTemporaryDirectory() + "phosphor-photos-\(udid.prefix(8))"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let localPath = (tmpDir as NSString).appendingPathComponent(uniqueLocalName(for: photo))

        // Only use cache if file is non-empty
        if fm.fileExists(atPath: localPath) {
            let size = (try? fm.attributesOfItem(atPath: localPath))?[.size] as? Int ?? 0
            if size > 0 { return (localPath, nil) }
            try? fm.removeItem(atPath: localPath)
        }

        let args = ["afc", "pull", photo.path, localPath, "--udid", udid]
        let result = await PyMobileDevice.runAsync(args, timeout: timeout)

        let pulledSize = (try? fm.attributesOfItem(atPath: localPath))?[.size] as? Int ?? 0
        if !result.succeeded || pulledSize == 0 {
            try? fm.removeItem(atPath: localPath)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let needsTunnel = stderr.lowercased().contains("tunnel") || stderr.lowercased().contains("lockdown")
                || stderr.lowercased().contains("timeout") || stderr.isEmpty
            if needsTunnel {
                return (nil, "Could not connect to device.\n\nOn iOS 17+, open Terminal and run:\n\nsudo pymobiledevice3 remote tunneld\n\nKeep it running, then try again.")
            }
            return (nil, "Download failed.\n\n\(stderr.isEmpty ? "Make sure the device is connected and unlocked." : stderr)")
        }
        return (localPath, nil)
    }

    /// Scan photos via ifuse mount (legacy).
    private func scanPhotosViaMount() async {
        guard let mount = mountPath else { return }

        let dcimPath = (mount as NSString).appendingPathComponent("DCIM")
        let fm = FileManager.default

        guard fm.fileExists(atPath: dcimPath) else {
            lastError = "DCIM folder not found on device"
            return
        }

        let photoExtensions = Set(["jpg", "jpeg", "heic", "heif", "png", "gif", "webp",
                                    "mov", "mp4", "m4v", "3gp"])
        var found: [LivePhoto] = []

        if let subfolders = try? fm.contentsOfDirectory(atPath: dcimPath) {
            for subfolder in subfolders.sorted() {
                let subPath = (dcimPath as NSString).appendingPathComponent(subfolder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue else { continue }

                if let files = try? fm.contentsOfDirectory(atPath: subPath) {
                    for file in files {
                        let ext = (file as NSString).pathExtension.lowercased()
                        guard photoExtensions.contains(ext) else { continue }

                        let fullPath = (subPath as NSString).appendingPathComponent(file)
                        let attrs = try? fm.attributesOfItem(atPath: fullPath)
                        let size = (attrs?[.size] as? UInt64) ?? 0
                        let modified = attrs?[.modificationDate] as? Date
                        let isVideo = ["mov", "mp4", "m4v", "3gp"].contains(ext)

                        found.append(LivePhoto(
                            id: fullPath, name: file, path: fullPath,
                            size: size, modified: modified, isVideo: isVideo
                        ))
                    }
                }
            }
        }

        photos = found.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    // MARK: - Export

    private func uniqueLocalName(for photo: LivePhoto) -> String {
        let stem = photo.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "_")
        return stem.isEmpty ? photo.name : stem
    }

    func exportPhoto(_ photo: LivePhoto, to destination: String) async throws {
        let fm = FileManager.default
        let destDir = (destination as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        if usesAFC {
            guard let udid = deviceUDID else { throw CocoaError(.fileNoSuchFile) }

            // Reuse cached preview file if already pulled and non-empty
            let cachedPath = localCachePath(for: photo, udid: udid)
            if fm.fileExists(atPath: cachedPath),
               let attrs = try? fm.attributesOfItem(atPath: cachedPath),
               (attrs[.size] as? Int ?? 0) > 0 {
                if fm.fileExists(atPath: destination) { try fm.removeItem(atPath: destination) }
                try fm.copyItem(atPath: cachedPath, toPath: destination)
                return
            }

            // Pull directly to destination
            let success = await PyMobileDevice.afcPull(remotePath: photo.path, localPath: destination, udid: udid)
            if !success { throw CocoaError(.fileWriteUnknown) }

            // Validate the exported file is non-empty
            let size = (try? fm.attributesOfItem(atPath: destination))?[.size] as? Int ?? 0
            if size == 0 { throw NSError(domain: "Phosphor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Exported file is empty — try again or check device connection"]) }
        } else {
            // Mount mode: local copy
            if fm.fileExists(atPath: destination) { try fm.removeItem(atPath: destination) }
            try fm.copyItem(atPath: photo.path, toPath: destination)
        }
    }

    private func localCachePath(for photo: LivePhoto, udid: String) -> String {
        let tmpDir = NSTemporaryDirectory() + "phosphor-photos-\(udid.prefix(8))"
        return (tmpDir as NSString).appendingPathComponent(uniqueLocalName(for: photo))
    }

    func exportPhotos(_ selectedPhotos: [LivePhoto], to directory: String) async -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var count = 0
        for photo in selectedPhotos {
            let dest = (directory as NSString).appendingPathComponent(uniqueLocalName(for: photo))
            do { try await exportPhoto(photo, to: dest); count += 1 } catch { continue }
        }
        return count
    }

    /// Convert HEIC photos to JPG using macOS sips.
    func convertHEICtoJPG(inputPath: String, outputPath: String) async -> Bool {
        let result = await Shell.runAsync("sips", arguments: [
            "--setProperty", "format", "jpeg", inputPath, "--out", outputPath
        ])
        return result.succeeded
    }

    // MARK: - Album Scanning

    /// Pull Photos.sqlite from the device and parse album structure.
    /// Requires photos to be scanned first so assets can be correlated.
    func scanAlbums() async {
        guard isMounted, let udid = deviceUDID else { return }
        albumsLoading = true

        let tmpDir = NSTemporaryDirectory() + "phosphor-photos-\(udid.prefix(8))"
        let tempPath = (tmpDir as NSString).appendingPathComponent("Photos.sqlite")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        var dbPath: String?

        if usesAFC {
            // Pull Photos.sqlite from device via AFC (/PhotoData/Photos.sqlite = Media root)
            let ok = await PyMobileDevice.afcPull(
                remotePath: "/PhotoData/Photos.sqlite",
                localPath: tempPath,
                udid: udid
            )
            if ok { dbPath = tempPath }
        } else if let mount = mountPath {
            let src = (mount as NSString).appendingPathComponent("PhotoData/Photos.sqlite")
            if fm.fileExists(atPath: src) {
                try? fm.copyItem(atPath: src, toPath: tempPath)
                dbPath = tempPath
            }
        }

        guard let path = dbPath else {
            albumsLoading = false
            return
        }

        albums = (try? Self.parseDeviceAlbums(dbPath: path, photos: photos)) ?? []
        albumsLoading = false
    }

    private struct JunctionInfo {
        let tableName: String
        let albumColumn: String
        let assetColumn: String
    }

    private static func parseDeviceAlbums(dbPath: String, photos: [LivePhoto]) throws -> [LiveAlbum] {
        let db = try SQLiteReader(path: dbPath)

        // Build lookups: photo.path is "/DCIM/<dir>/<file>" in AFC mode
        var byPath: [String: LivePhoto] = [:]
        var byFilename: [String: LivePhoto] = [:]
        for photo in photos {
            byPath[photo.path.lowercased()] = photo
            if byFilename[photo.name.lowercased()] == nil {
                byFilename[photo.name.lowercased()] = photo
            }
        }

        guard let junction = try findJunctionTable(in: db) else { return [] }

        let albumRows = try db.query(
            "SELECT Z_PK, ZTITLE, ZKIND FROM ZGENERICALBUM WHERE ZTITLE IS NOT NULL AND ZTITLE != '' ORDER BY ZTITLE"
        )

        var result: [LiveAlbum] = []
        for albumRow in albumRows {
            guard let pk = albumRow["Z_PK"] as? Int,
                  let title = albumRow["ZTITLE"] as? String else { continue }
            let kindInt = (albumRow["ZKIND"] as? Int) ?? 2
            let kind: PhotoAlbum.Kind = kindInt >= 1500 ? .smart : .regular

            let sql = """
                SELECT a.ZDIRECTORY, a.ZFILENAME
                FROM ZASSET a
                JOIN \(junction.tableName) j ON a.Z_PK = j.\(junction.assetColumn)
                WHERE j.\(junction.albumColumn) = \(pk)
                ORDER BY a.ZDATECREATED
                """
            let assetRows = (try? db.query(sql)) ?? []

            var albumPhotos: [LivePhoto] = []
            for assetRow in assetRows {
                guard let filename = assetRow["ZFILENAME"] as? String else { continue }
                if let dir = assetRow["ZDIRECTORY"] as? String,
                   let photo = byPath["/dcim/\(dir.lowercased())/\(filename.lowercased())"] {
                    albumPhotos.append(photo)
                } else if let photo = byFilename[filename.lowercased()] {
                    albumPhotos.append(photo)
                }
            }

            guard !albumPhotos.isEmpty else { continue }
            result.append(LiveAlbum(id: pk, title: title, kind: kind, photos: albumPhotos))
        }

        return result
    }

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

    // MARK: - General File Listing

    func listFiles(at relativePath: String) -> [(name: String, isDir: Bool, size: UInt64)] {
        guard let mount = mountPath else { return [] }
        let fullPath = (mount as NSString).appendingPathComponent(relativePath)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: fullPath) else { return [] }
        return contents.sorted().compactMap { name in
            let itemPath = (fullPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: itemPath, isDirectory: &isDir)
            let attrs = try? fm.attributesOfItem(atPath: itemPath)
            let size = (attrs?[.size] as? UInt64) ?? 0
            return (name: name, isDir: isDir.boolValue, size: size)
        }
    }

    func getTopLevelFolders() -> [String] {
        guard let mount = mountPath else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: mount) else { return [] }
        return contents.sorted().filter { name in
            var isDir: ObjCBool = false
            let path = (mount as NSString).appendingPathComponent(name)
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}
