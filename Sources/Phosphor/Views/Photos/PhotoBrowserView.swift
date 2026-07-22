import SwiftUI
import CoreGraphics
import AVFoundation

/// Browse and extract photos/videos from backup Camera Roll OR directly from connected device.
struct PhotoBrowserView: View {

    @EnvironmentObject var deviceVM: DeviceViewModel
    @EnvironmentObject var backupVM: BackupViewModel
    @StateObject private var photoVM = PhotoViewModel()
    @StateObject private var liveBrowser = LiveDeviceBrowser()
    @State private var selectedItems: Set<String> = []
    @State private var filterType: MediaItem.MediaType?
    @State private var viewMode: ViewMode = .grid
    @State private var sourceMode: SourceMode = .device
    @State private var browseMode: BrowseMode = .byType
    @State private var selectedAlbum: PhotoAlbum?
    @State private var deviceBrowseMode: BrowseMode = .byType
    @State private var selectedDeviceAlbum: LiveDeviceBrowser.LiveAlbum?
    @State private var previewPhoto: LiveDeviceBrowser.LivePhoto?
    @State private var deviceFilter: DeviceFilter = .all
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var thumbnailLoadingIDs: Set<String> = []
    @State private var thumbnailQueue: [LiveDeviceBrowser.LivePhoto] = []

    enum DeviceFilter { case all, photos, videos }

    enum ViewMode { case grid, list }
    enum SourceMode: String, CaseIterable {
        case device = "From Device"
        case backup = "From Backup"
    }
    enum BrowseMode { case byType, byAlbum }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            switch sourceMode {
            case .device:
                devicePhotoView
            case .backup:
                backupPhotoView
            }
        }
        .onAppear {
            if deviceVM.selectedDevice != nil && !liveBrowser.isMounted {
                Task {
                    if let udid = deviceVM.selectedDevice?.id {
                        let ok = await liveBrowser.mount(udid: udid)
                        if ok { await liveBrowser.scanPhotos() }
                    }
                }
            }
            if let backup = backupVM.selectedBackup {
                Task { await photoVM.loadPhotos(from: backup.path) }
            }
        }
        .alert("Photos", isPresented: $photoVM.showAlert) {
            Button("OK") {}
        } message: {
            Text(photoVM.alertMessage)
        }
        .sheet(item: $previewPhoto) { photo in
            PhotoPreviewSheet(photo: photo, browser: liveBrowser)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 14) {
            GradientIconTile(systemName: "photo.on.rectangle.angled", color: .orange, size: 40, iconSize: 19)

            VStack(alignment: .leading, spacing: 2) {
                Text("Photos & Videos")
                    .font(.title2.weight(.semibold))

                if sourceMode == .device {
                    Text("\(liveBrowser.photos.count) items on device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let stats = photoVM.stats
                    if stats.photos > 0 || stats.videos > 0 {
                        Text("\(stats.photos) photos, \(stats.videos) videos · \(stats.totalSize.formattedFileSize)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Picker("Source", selection: $sourceMode) {
                ForEach(SourceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 72)

            Button {
                if sourceMode == .device {
                    extractFromDevice()
                } else {
                    extractFromBackup()
                }
            } label: {
                Label(
                    selectedItems.isEmpty ? "Extract All" : "Extract (\(selectedItems.count))",
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandAccent)
        }
        .padding(20)
    }

    // MARK: - Device Photos (Live)

    private var devicePhotoView: some View {
        Group {
            if liveBrowser.isLoading {
                LoadingOverlay(message: "Scanning Camera Roll from device...")
            } else if !liveBrowser.isMounted {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: deviceVM.selectedDevice == nil ? "No Device Connected" : "Device Not Mounted",
                    subtitle: "Connect your device via USB to browse photos directly without a backup. Uses pymobiledevice3 AFC on macOS.",
                    action: {
                        guard let udid = deviceVM.selectedDevice?.id else { return }
                        Task {
                            let ok = await liveBrowser.mount(udid: udid)
                            if ok { await liveBrowser.scanPhotos() }
                        }
                    },
                    actionLabel: deviceVM.selectedDevice != nil ? "Mount Device" : nil
                )
            } else if liveBrowser.photos.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No Photos Found",
                    subtitle: "DCIM folder is empty or inaccessible.",
                    action: { Task { await liveBrowser.scanPhotos() } },
                    actionLabel: "Scan Again"
                )
            } else {
                deviceContentView
            }
        }
    }

    private var deviceContentView: some View {
        VStack(spacing: 0) {
            // Browse mode picker + back button
            HStack(spacing: 0) {
                Picker("Browse Mode", selection: $deviceBrowseMode) {
                    Text("By Type").tag(BrowseMode.byType)
                    Text("By Album").tag(BrowseMode.byAlbum)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(.leading, 16)

                Spacer()

                if deviceBrowseMode == .byAlbum && selectedDeviceAlbum != nil {
                    Button {
                        selectedDeviceAlbum = nil
                        selectedItems.removeAll()
                    } label: {
                        Label("All Albums", systemImage: "chevron.left")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandAccent)
                    .padding(.trailing, 16)
                }
            }
            .padding(.vertical, 10)

            Divider()

            // Type filter strip (only in By Type mode)
            if deviceBrowseMode == .byType {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deviceFilterChip(.all, label: "All", icon: "photo.on.rectangle")
                        deviceFilterChip(.photos, label: "Photos", icon: "photo")
                        deviceFilterChip(.videos, label: "Videos", icon: "video")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            // Album breadcrumb
            if deviceBrowseMode == .byAlbum, let album = selectedDeviceAlbum {
                HStack(spacing: 8) {
                    Image(systemName: album.kind.sfSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(album.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(album.photoCount) items")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
            }

            deviceBodyView
        }
        .onChange(of: deviceBrowseMode) { _, _ in
            selectedDeviceAlbum = nil
            selectedItems.removeAll()
            deviceFilter = .all
            if deviceBrowseMode == .byAlbum && liveBrowser.albums.isEmpty {
                Task { await liveBrowser.scanAlbums() }
            }
        }
    }

    @ViewBuilder
    private var deviceBodyView: some View {
        switch deviceBrowseMode {
        case .byType:
            liveMediaView
        case .byAlbum:
            deviceAlbumBrowseView
        }
    }

    @ViewBuilder
    private var liveMediaView: some View {
        switch viewMode {
        case .grid: liveGridView
        case .list: liveListView
        }
    }

    @ViewBuilder
    private var deviceAlbumBrowseView: some View {
        if liveBrowser.albumsLoading {
            LoadingOverlay(message: "Loading albums from device…")
        } else if let album = selectedDeviceAlbum {
            liveAlbumDetailView(album)
        } else {
            deviceAlbumGridView
        }
    }

    private var deviceAlbumGridView: some View {
        Group {
            if liveBrowser.albums.isEmpty {
                EmptyStateView(
                    icon: "rectangle.stack",
                    title: "No Albums Found",
                    subtitle: "Could not read Photos.sqlite from device. Make sure pymobiledevice3 is installed."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                        ForEach(liveBrowser.albums) { album in
                            deviceAlbumCard(album)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func deviceAlbumCard(_ album: LiveDeviceBrowser.LiveAlbum) -> some View {
        Button {
            selectedDeviceAlbum = album
            selectedItems.removeAll()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .frame(height: 110)
                    Image(systemName: album.kind.sfSymbol)
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            let videos = album.photos.filter { $0.isVideo }.count
                            if videos > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "video.fill").font(.system(size: 8))
                                    Text("\(videos)").font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.55))
                                .clipShape(Capsule())
                                .padding(6)
                            }
                        }
                    }
                }
                .frame(height: 110)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(album.photoCount) items")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func liveAlbumDetailView(_ album: LiveDeviceBrowser.LiveAlbum) -> some View {
        let photos = filteredAlbumPhotos(album.photos)
        switch viewMode {
        case .grid:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
                    ForEach(photos) { photo in livePhotoCell(photo) }
                }
                .padding(16)
            }
        case .list:
            List(photos) { photo in
                HStack(spacing: 10) {
                    Image(systemName: photo.sfSymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(photo.name).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(photo.sizeString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
    }

    private var filteredLivePhotos: [LiveDeviceBrowser.LivePhoto] {
        switch deviceFilter {
        case .all: return liveBrowser.photos
        case .photos: return liveBrowser.photos.filter { !$0.isVideo }
        case .videos: return liveBrowser.photos.filter { $0.isVideo }
        }
    }

    private func filteredAlbumPhotos(_ photos: [LiveDeviceBrowser.LivePhoto]) -> [LiveDeviceBrowser.LivePhoto] {
        switch deviceFilter {
        case .all: return photos
        case .photos: return photos.filter { !$0.isVideo }
        case .videos: return photos.filter { $0.isVideo }
        }
    }

    private var liveGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(filteredLivePhotos) { photo in
                    livePhotoCell(photo)
                }
            }
            .padding(16)
        }
    }

    private func livePhotoCell(_ photo: LiveDeviceBrowser.LivePhoto) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
                    .frame(height: 100)

                // Thumbnail or placeholder
                if let thumb = thumbnails[photo.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: photo.isVideo ? "video.fill" : "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        let ext = (photo.name as NSString).pathExtension.uppercased()
                        Text(ext)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Selection border
                if selectedItems.contains(photo.id) {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.brandAccent, lineWidth: 3)
                }

                // Video badge (bottom-right)
                if photo.isVideo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                                .padding(6)
                        }
                    }
                }

                // Checkbox (top-left) — separate interaction from preview tap
                VStack {
                    HStack {
                        Image(systemName: selectedItems.contains(photo.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(selectedItems.contains(photo.id)
                                             ? Color.brandAccent : Color.white)
                            .background(Circle().fill(
                                selectedItems.contains(photo.id)
                                    ? Color.white : Color.black.opacity(0.3)
                            ).padding(2))
                            .onTapGesture { toggleSelection(photo.id) }
                            .padding(6)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(height: 100)
            .onTapGesture { openPreview(photo) }
            .onAppear { loadThumbnail(photo) }

            Text(photo.name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func loadThumbnail(_ photo: LiveDeviceBrowser.LivePhoto) {
        guard thumbnails[photo.id] == nil,
              !thumbnailLoadingIDs.contains(photo.id),
              previewPhoto == nil else { return }

        // For videos: only generate thumbnail from already-cached file
        if photo.isVideo {
            if let path = liveBrowser.cachedPath(for: photo) {
                startVideoThumbnail(photo, localPath: path)
            }
            return
        }

        // Photos: queue if at concurrency limit
        if thumbnailLoadingIDs.count < 3 {
            startPhotoThumbnail(photo)
        } else if !thumbnailQueue.contains(where: { $0.id == photo.id }) {
            thumbnailQueue.append(photo)
        }
    }

    private func startPhotoThumbnail(_ photo: LiveDeviceBrowser.LivePhoto) {
        thumbnailLoadingIDs.insert(photo.id)
        Task {
            defer {
                thumbnailLoadingIDs.remove(photo.id)
                // Dequeue next pending thumbnail
                while !thumbnailQueue.isEmpty {
                    let next = thumbnailQueue.removeFirst()
                    if thumbnails[next.id] == nil && !thumbnailLoadingIDs.contains(next.id) {
                        startPhotoThumbnail(next)
                        break
                    }
                }
            }
            guard let path = (await liveBrowser.pullPhoto(photo, timeout: 20)).path else { return }
            guard !Task.isCancelled else { return }
            let cfURL = URL(fileURLWithPath: path) as CFURL
            guard let src = CGImageSourceCreateWithURL(cfURL, nil) else { return }
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 300,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return }
            thumbnails[photo.id] = NSImage(cgImage: cgThumb,
                                           size: NSSize(width: CGFloat(cgThumb.width), height: CGFloat(cgThumb.height)))
        }
    }

    private func startVideoThumbnail(_ photo: LiveDeviceBrowser.LivePhoto, localPath: String) {
        thumbnailLoadingIDs.insert(photo.id)
        Task {
            defer { thumbnailLoadingIDs.remove(photo.id) }
            let url = URL(fileURLWithPath: localPath)
            let thumb = await Task.detached(priority: .utility) {
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 300, height: 300)
                guard let cgImg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil as NSImage? }
                return NSImage(cgImage: cgImg, size: .zero)
            }.value
            guard let thumb, !Task.isCancelled else { return }
            thumbnails[photo.id] = thumb
        }
    }

    private func openPreview(_ photo: LiveDeviceBrowser.LivePhoto) {
        previewPhoto = photo
    }

    private var liveListView: some View {
        List(filteredLivePhotos) { photo in
            HStack(spacing: 10) {
                if photo.path.hasPrefix("/DCIM"), true {
                    Image(systemName: photo.sfSymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if let nsImage = NSImage(contentsOfFile: photo.path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: photo.sfSymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(photo.name).font(.system(size: 13)).lineLimit(1)
                    if let date = photo.modified {
                        Text(date.shortString).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(photo.sizeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
    }

    // MARK: - Backup Photos

    private var backupPhotoView: some View {
        Group {
            if photoVM.isLoading {
                LoadingOverlay(message: "Scanning Camera Roll from backup...")
            } else if backupVM.selectedBackup == nil && backupVM.backups.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No Backup Available",
                    subtitle: "Create a backup first, or switch to 'From Device' to browse photos directly.",
                    action: nil, actionLabel: nil
                )
            } else if backupVM.selectedBackup == nil {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No Backup Selected",
                    subtitle: "Go to Backups, select a backup, then return here.",
                    action: {
                        if let first = backupVM.backups.first {
                            backupVM.openBackupBrowser(first)
                            Task { await photoVM.loadPhotos(from: first.path) }
                        }
                    },
                    actionLabel: backupVM.backups.isEmpty ? nil : "Use Latest Backup"
                )
            } else if photoVM.items.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No Photos in Backup",
                    subtitle: "This backup doesn't contain Camera Roll photos, or it may be encrypted."
                )
            } else {
                backupContentView
            }
        }
    }

    private var backupContentView: some View {
        VStack(spacing: 0) {
            // Browse mode picker + back button
            HStack(spacing: 0) {
                Picker("Browse Mode", selection: $browseMode) {
                    Text("By Type").tag(BrowseMode.byType)
                    Text("By Album").tag(BrowseMode.byAlbum)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(.leading, 16)

                Spacer()

                if browseMode == .byAlbum && selectedAlbum != nil {
                    Button {
                        selectedAlbum = nil
                        selectedItems.removeAll()
                    } label: {
                        Label("All Albums", systemImage: "chevron.left")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandAccent)
                    .padding(.trailing, 16)
                }
            }
            .padding(.vertical, 10)

            Divider()

            // Type filter strip (only in By Type mode)
            if browseMode == .byType {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, label: "All", icon: "photo.on.rectangle")
                        filterChip(.photo, label: "Photos", icon: "photo")
                        filterChip(.video, label: "Videos", icon: "video")
                        filterChip(.screenshot, label: "Screenshots", icon: "rectangle.dashed")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            // Album breadcrumb when drilling into an album
            if browseMode == .byAlbum, let album = selectedAlbum {
                HStack(spacing: 8) {
                    Image(systemName: album.kind.sfSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(album.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(album.itemCount) items")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
            }

            backupBodyView
        }
        .onChange(of: browseMode) { _, _ in
            selectedAlbum = nil
            selectedItems.removeAll()
        }
    }

    @ViewBuilder
    private var backupBodyView: some View {
        switch browseMode {
        case .byType:
            backupMediaView
        case .byAlbum:
            albumBrowseView
        }
    }

    @ViewBuilder
    private var backupMediaView: some View {
        switch viewMode {
        case .grid: backupGridView
        case .list: backupListView
        }
    }

    @ViewBuilder
    private var albumBrowseView: some View {
        if photoVM.albumService.isLoading {
            LoadingOverlay(message: "Loading albums…")
        } else if selectedAlbum != nil {
            backupMediaView
        } else {
            albumGridView
        }
    }

    // MARK: - Album Grid

    private var albumGridView: some View {
        Group {
            if photoVM.albumService.albums.isEmpty {
                EmptyStateView(
                    icon: "rectangle.stack",
                    title: "No Albums Found",
                    subtitle: "Photos.sqlite was not found in this backup, or no user albums exist."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                        ForEach(photoVM.albumService.albums) { album in
                            albumCard(album)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func albumCard(_ album: PhotoAlbum) -> some View {
        Button {
            selectedAlbum = album
            selectedItems.removeAll()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .frame(height: 110)
                    Image(systemName: album.kind.sfSymbol)
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    // Show media type breakdown in corner
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            let videos = album.items.filter { $0.mediaType == .video }.count
                            if videos > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "video.fill").font(.system(size: 8))
                                    Text("\(videos)").font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.55))
                                .clipShape(Capsule())
                                .padding(6)
                            }
                        }
                    }
                }
                .frame(height: 110)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(album.itemCount) items")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if album.kind == .smart {
                            Text("·")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 11))
                            Text(album.kind.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Backup Grid / List

    private var backupGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
                ForEach(displayedItems) { item in
                    backupGridCell(item)
                }
            }
            .padding(16)
        }
    }

    private func backupGridCell(_ item: MediaItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
                    .frame(height: 100)
                Image(systemName: item.mediaType.sfSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                if selectedItems.contains(item.id) {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.brandAccent, lineWidth: 3)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brandAccent)
                        .background(Circle().fill(.white).padding(2))
                        .position(x: 20, y: 20)
                }
            }
            .frame(height: 100)
            .onTapGesture { toggleSelection(item.id) }

            Text(item.filename)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var backupListView: some View {
        List(displayedItems, selection: $selectedItems) { item in
            HStack(spacing: 10) {
                Image(systemName: item.mediaType.sfSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.filename).font(.system(size: 13)).lineLimit(1)
                    Text(item.relativePath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.sizeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
    }

    // MARK: - Helpers

    private var displayedItems: [MediaItem] {
        if browseMode == .byAlbum, let album = selectedAlbum {
            return album.items
        }
        guard let filter = filterType else { return photoVM.items }
        return photoVM.items.filter { $0.mediaType == filter }
    }

    private func deviceFilterChip(_ filter: DeviceFilter, label: String, icon: String) -> some View {
        Button { deviceFilter = filter } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(deviceFilter == filter ? Color.brandAccent : Color(.controlBackgroundColor))
            .foregroundStyle(deviceFilter == filter ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ type: MediaItem.MediaType?, label: String, icon: String) -> some View {
        Button { filterType = type } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filterType == type ? Color.brandAccent : Color(.controlBackgroundColor))
            .foregroundStyle(filterType == type ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ id: String) {
        if selectedItems.contains(id) { selectedItems.remove(id) } else { selectedItems.insert(id) }
    }

    private func extractFromDevice() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Extract Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let sourcePhotos: [LiveDeviceBrowser.LivePhoto]
        if deviceBrowseMode == .byAlbum, let album = selectedDeviceAlbum {
            sourcePhotos = album.photos
        } else {
            sourcePhotos = liveBrowser.photos
        }

        let photosToExtract: [LiveDeviceBrowser.LivePhoto]
        if selectedItems.isEmpty {
            photosToExtract = sourcePhotos
        } else {
            photosToExtract = sourcePhotos.filter { selectedItems.contains($0.id) }
        }
        Task {
            let count = await liveBrowser.exportPhotos(photosToExtract, to: url.path)
            if count > 0 { NSWorkspace.shared.open(url) }
        }
    }

    private func extractFromBackup() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Extract Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard backupVM.selectedBackup != nil else { return }

        let itemsToExtract: [MediaItem]
        if selectedItems.isEmpty {
            itemsToExtract = displayedItems
        } else {
            itemsToExtract = displayedItems.filter { selectedItems.contains($0.id) }
        }
        Task {
            let count = await photoVM.extractSelected(itemsToExtract, to: url.path)
            if count > 0 { NSWorkspace.shared.open(url) }
        }
    }
}
