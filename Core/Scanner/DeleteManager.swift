import Foundation
import Photos

/// 照片与视频删除管理器
/// 将所选项目移至「最近删除」而非永久删除，提供 30 天恢复窗口
final class DeleteManager {
    
    /// 删除结果
    struct DeleteResult {
        let successCount: Int
        let failedCount: Int
        let freedSpace: Int64
        let failedIDs: [String]
        let errors: [Error]
    }
    
    /// 批量删除照片
    /// - Parameter photos: 待删除的照片列表
    /// - Returns: 删除结果
    func deletePhotos(_ photos: [PhotoItem]) async -> DeleteResult {
        var successCount = 0
        var failedIDs: [String] = []
        var errors: [Error] = []
        var freedSpace: Int64 = 0
        
        // 分批处理，每批最多 100 张
        let batchSize = 100
        let batches = stride(from: 0, to: photos.count, by: batchSize).map {
            Array(photos[$0..<min($0 + batchSize, photos.count)])
        }
        
        for batch in batches {
            do {
                try await deleteBatch(batch)
                successCount += batch.count
                freedSpace += batch.reduce(0) { $0 + $1.fileSize }
            } catch {
                if (error as NSError).domain == "PHPhotosErrorDomain" {
                    failedIDs.append(contentsOf: batch.map(\.id))
                    errors.append(error)
                    continue
                }

                // 单张删除降级方案
                for photo in batch {
                    do {
                        try await deleteSingle(photo)
                        successCount += 1
                        freedSpace += photo.fileSize
                    } catch {
                        failedIDs.append(photo.id)
                        errors.append(error)
                    }
                }
            }
        }
        
        return DeleteResult(
            successCount: successCount,
            failedCount: failedIDs.count,
            freedSpace: freedSpace,
            failedIDs: failedIDs,
            errors: errors
        )
    }
    
    /// 批量删除（使用 PHAssetChangeRequest）
    private func deleteBatch(_ photos: [PhotoItem]) async throws {
        let assets = photos.map { $0.asset }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }
    
    /// 单张删除
    private func deleteSingle(_ photo: PhotoItem) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([photo.asset] as NSArray)
        }
    }
    
    /// 从「最近删除」中恢复照片
    func recoverPhotos(_ photos: [PhotoItem]) async throws {
        // 注意：从「最近删除」恢复需要通过 PHAsset 的删除标记
        // 实际上 PHPhotoLibrary 不提供直接恢复 API
        // 用户需在系统「照片」App 的「最近删除」中手动恢复
        throw DeleteError.recoveryNotSupported
    }
    
    enum DeleteError: LocalizedError {
        case recoveryNotSupported
        
        var errorDescription: String? {
            switch self {
            case .recoveryNotSupported:
                return "请前往系统「照片」App 的「最近删除」相簿中恢复照片"
            }
        }
    }
}
