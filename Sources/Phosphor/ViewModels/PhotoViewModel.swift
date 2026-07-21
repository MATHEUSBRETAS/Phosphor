import Foundation
import SwiftUI
import Combine

/// Drives photo/video browsing and extraction UI.
@MainActor
final class PhotoViewModel: ObservableObject {

    @Published var items: [MediaItem] = []
    @Published var isLoading = false
    @Published var selectedFilter: MediaItem.MediaType?
    @Published var extractionProgress: Double = 0
    @Published var showAlert = false
    @Published var alertMessage = ""

    let photoExtractor = PhotoExtractor()
    let albumService = AlbumService()
    private var backupPath: String?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward albumService changes so the view re-renders when albums load.
        albumService.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var filteredItems: [MediaItem] {
        photoExtractor.filtered(by: selectedFilter)
    }

    var stats: (photos: Int, videos: Int, totalSize: Int) {
        photoExtractor.stats
    }

    func loadPhotos(from backupPath: String) async {
        self.backupPath = backupPath
        isLoading = true
        await photoExtractor.loadMedia(from: backupPath)
        items = photoExtractor.mediaItems
        isLoading = false
        // Load album metadata after all items are available
        await albumService.loadAlbums(from: backupPath, allItems: items)
    }

    func extractSelected(_ items: [MediaItem], to destination: String) async -> Int {
        guard let path = backupPath else { return 0 }
        let count = await photoExtractor.extractMedia(items: items, from: path, to: destination)
        alertMessage = "Extracted \(count) files"
        showAlert = true
        return count
    }

    func extractAll(to destination: String) async -> Int {
        await extractSelected(items, to: destination)
    }

    func extractAlbum(_ album: PhotoAlbum, to destination: String) async -> Int {
        guard let path = backupPath else { return 0 }
        let count = await albumService.extractAlbum(album, from: path, to: destination)
        alertMessage = "Extracted \(count) files from \"\(album.title)\""
        showAlert = true
        return count
    }
}
