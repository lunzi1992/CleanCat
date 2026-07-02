import Foundation
import Photos

/// 扫描结果总览
struct ScanResults {
    let totalPhotoCount: Int
    let duplicateGroups: [DuplicateGroup]
    let similarGroups: [SimilarGroup]
    let screenshots: [PhotoItem]
    let screenRecordings: [PhotoItem]
    let scanDuration: TimeInterval
    
    /// 预计可释放空间（字节）
    var totalReclaimableSpace: Int64 {
        var space: Int64 = 0
        for group in duplicateGroups {
            // 每组保留一张，其余可删
            space += group.photos.dropFirst().reduce(0) { $0 + $1.fileSize }
        }
        for group in similarGroups {
            // 默认保留建议保留的一张，其余可删
            let sorted = group.photos.sorted { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
            space += sorted.dropFirst().reduce(0) { $0 + $1.fileSize }
        }
        for photo in screenshots {
            space += photo.fileSize
        }
        for recording in screenRecordings {
            space += recording.fileSize
        }
        return space
    }
    
    var totalReclaimableCount: Int {
        let duplicateCount = duplicateGroups.reduce(0) { $0 + $1.photos.count - 1 }
        let similarCount = similarGroups.reduce(0) { $0 + $1.photos.count - 1 }
        return duplicateCount + similarCount + screenshots.count + screenRecordings.count
    }

    func removing(photoIDs deletedIDs: Set<String>) -> ScanResults {
        let duplicates = duplicateGroups.compactMap { group -> DuplicateGroup? in
            let remaining = group.photos.filter { !deletedIDs.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return DuplicateGroup(md5Hash: group.md5Hash, photos: remaining)
        }

        let similar = similarGroups.compactMap { group -> SimilarGroup? in
            let remaining = group.photos.filter { !deletedIDs.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return SimilarGroup(photos: remaining)
        }

        return ScanResults(
            totalPhotoCount: max(0, totalPhotoCount - deletedIDs.count),
            duplicateGroups: duplicates,
            similarGroups: similar,
            screenshots: screenshots.filter { !deletedIDs.contains($0.id) },
            screenRecordings: screenRecordings.filter { !deletedIDs.contains($0.id) },
            scanDuration: scanDuration
        )
    }
}

/// 单张照片数据
struct PhotoItem: Identifiable, Hashable {
    let id: String  // PHAsset.localIdentifier
    let asset: PHAsset
    var md5Hash: String?
    let pHash: UInt64?
    let isScreenshot: Bool
    let isScreenRecording: Bool
    let fileSize: Int64
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    var qualityScore: Double?
    var qualityReason: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// 完全重复照片组（MD5 相同）
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let md5Hash: String
    let photos: [PhotoItem]
    
    var duplicateCount: Int { photos.count - 1 }
    var reclaimableSpace: Int64 {
        photos.dropFirst().reduce(0) { $0 + $1.fileSize }
    }
}

/// 相似照片组（pHash 汉明距离 ≤ 阈值）
struct SimilarGroup: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
    var bestPhoto: PhotoItem? {
        photos.max { ($0.qualityScore ?? 0) < ($1.qualityScore ?? 0) }
    }
    
    var reclaimableSpace: Int64 {
        let sorted = photos.sorted { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
        return sorted.dropFirst().reduce(0) { $0 + $1.fileSize }
    }
}
