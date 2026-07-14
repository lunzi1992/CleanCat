import Foundation
import Photos

/// 扫描结果总览
struct ScanResults {
    let totalPhotoCount: Int
    let duplicateGroups: [DuplicateGroup]
    let similarGroups: [SimilarGroup]
    let screenshots: [PhotoItem]
    let screenRecordings: [PhotoItem]
    let lowQualityPhotos: [PhotoItem]
    let cloudOnlyPhotoCount: Int
    let livePhotoCount: Int
    let scanDuration: TimeInterval
    
    /// 预计可释放空间（字节）
    var totalReclaimableSpace: Int64 {
        reclaimablePhotos.reduce(0) { $0 + $1.fileSize }
    }

    var totalReclaimableCount: Int {
        reclaimablePhotos.count
    }

    /// 重复照片优先，其次才是相似照片与截图。一个资源只计入一次，
    /// 让“可释放”估算与用户实际可选删除的范围一致。
    var reclaimablePhotos: [PhotoItem] {
        var seenIDs = Set(duplicateGroups.compactMap { $0.photos.first?.id })
        var photos: [PhotoItem] = []

        func appendIfNeeded(_ photo: PhotoItem) {
            guard seenIDs.insert(photo.id).inserted else { return }
            photos.append(photo)
        }

        for group in duplicateGroups {
            group.photos.dropFirst().forEach(appendIfNeeded)
        }
        for group in similarGroups {
            group.photos
                .sorted(by: PhotoItem.isPreferredForRecommendation)
                .dropFirst()
                .forEach(appendIfNeeded)
        }
        screenshots.forEach(appendIfNeeded)
        screenRecordings.forEach(appendIfNeeded)
        return photos
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
            lowQualityPhotos: lowQualityPhotos.filter { !deletedIDs.contains($0.id) },
            cloudOnlyPhotoCount: cloudOnlyPhotoCount,
            livePhotoCount: livePhotoCount,
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
    let isLivePhoto: Bool
    let isCloudOnly: Bool
    let fileSize: Int64
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let colorSignature: ColorSignature?
    var qualityScore: Double?
    var qualityReason: String?
    var technicalQualityScore: Double?
    var qualityIssueReason: String?
    var containsFace: Bool = false
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }

    /// 保留选择必须稳定：优先收藏照片，再保留较新的版本，最后用资源 ID 打破平局。
    static func isPreferredForRetention(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        if lhs.asset.isFavorite != rhs.asset.isFavorite {
            return lhs.asset.isFavorite
        }

        let lhsDate = lhs.creationDate ?? .distantPast
        let rhsDate = rhs.creationDate ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.id < rhs.id
    }

    /// 相似组优先采用质量评分；分数相同或不可用时，复用稳定的保留规则。
    static func isPreferredForRecommendation(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        let lhsScore = lhs.qualityScore ?? 0
        let rhsScore = rhs.qualityScore ?? 0
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return isPreferredForRetention(lhs, rhs)
    }
}

struct ColorSignature: Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let saturation: Double
    let brightness: Double
    let tileAverages: [Double]
}

/// 完全重复照片组（MD5 相同）
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let md5Hash: String
    let photos: [PhotoItem]

    var confidence: RecommendationConfidence { .high }
    var reasonTags: [String] { ["完全相同文件", "大小尺寸一致", "本地哈希匹配"] }
    
    var duplicateCount: Int { photos.count - 1 }
    var reclaimableSpace: Int64 {
        photos.dropFirst().reduce(0) { $0 + $1.fileSize }
    }
}

enum RecommendationConfidence: Equatable {
    case high
    case cautious

    var title: String {
        switch self {
        case .high: return "高可信"
        case .cautious: return "谨慎检查"
        }
    }

    var systemImage: String {
        switch self {
        case .high: return "checkmark.shield.fill"
        case .cautious: return "exclamationmark.triangle.fill"
        }
    }
}

/// 相似照片组（多维特征保守判断）
struct SimilarGroup: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]

    var bestPhoto: PhotoItem? {
        photos.sorted(by: PhotoItem.isPreferredForRecommendation).first
    }

    var confidence: RecommendationConfidence {
        photos.contains(where: \.containsFace) ? .cautious : .high
    }

    var reasonTags: [String] {
        var tags = ["视觉高度相似", "颜色构图接近", "同一时间段"]
        if photos.contains(where: \.containsFace) {
            tags.insert("含人脸，谨慎处理", at: 0)
        }
        return tags
    }
    
    var reclaimableSpace: Int64 {
        let sorted = photos.sorted(by: PhotoItem.isPreferredForRecommendation)
        return sorted.dropFirst().reduce(0) { $0 + $1.fileSize }
    }
}
