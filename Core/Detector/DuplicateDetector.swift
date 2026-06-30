import Foundation

/// 完全重复照片检测器
/// 基于 MD5 文件哈希：哈希值相同的照片判定为完全重复
final class DuplicateDetector {
    
    /// 检测重复照片并分组
    /// - Parameter photos: 所有照片列表
    /// - Returns: 重复照片分组（每组 ≥ 2 张）
    func detectDuplicates(in photos: [PhotoItem]) -> [DuplicateGroup] {
        // 按 MD5 哈希分组
        var hashGroups: [String: [PhotoItem]] = [:]
        
        for photo in photos {
            guard let hash = photo.md5Hash else { continue }
            hashGroups[hash, default: []].append(photo)
        }
        
        // 过滤出 ≥ 2 张的组，按照片数量降序排列
        let duplicateGroups = hashGroups
            .filter { $0.value.count >= 2 }
            .map { DuplicateGroup(md5Hash: $0.key, photos: $0.value) }
            .sorted { $0.photos.count > $1.photos.count }
        
        return duplicateGroups
    }
}
