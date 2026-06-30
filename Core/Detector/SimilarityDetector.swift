import Foundation
import UIKit

/// 相似照片检测器
/// 基于感知哈希（pHash）：将图片缩放为 8x8 灰度图，比较汉明距离
final class SimilarityDetector {
    
    /// 汉明距离阈值：≤ 此值的两张照片视为相似
    /// PRD V1.1 REQ-004：遵循"宁可漏判不可误判"原则
    /// 初始阈值保守（≤8 而非 10），后续根据 delete_cancelled 埋点调优
    static let hammingThreshold: Int = 8
    
    /// 最小分组数量：相似组至少需要 2 张照片
    static let minGroupSize: Int = 2

    /// 单张照片最多向后比较的数量。避免大年份相册进入 O(n²) 假死。
    private static let maxForwardComparisons = 40
    
    // MARK: - pHash 计算
    
    /// 计算感知哈希值（简化版 64-bit pHash）
    /// 算法：缩放到 8x8 → 转灰度 → 计算 DCT → 取低频 → 与均值比较
    static func computePHash(from image: UIImage) -> UInt64 {
        guard let cgImage = image.cgImage else { return 0 }
        
        // 1. 缩放到 32x32（为后续 DCT 准备）
        let size = CGSize(width: 32, height: 32)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return 0 }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
              let resizedCG = resizedImage.cgImage else { return 0 }
        
        // 2. 提取灰度像素值
        guard let dataProvider = resizedCG.dataProvider,
              let pixelData = dataProvider.data else { return 0 }
        
        let data = CFDataGetBytePtr(pixelData)
        let bytesPerPixel = 4
        let width = 32
        let height = 32
        
        var grayPixels: [Double] = []
        grayPixels.reserveCapacity(width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Double(data?[offset] ?? 0)
                let g = Double(data?[offset + 1] ?? 0)
                let b = Double(data?[offset + 2] ?? 0)
                // 加权灰度
                let gray = 0.299 * r + 0.587 * g + 0.114 * b
                grayPixels.append(gray)
            }
        }
        
        // 3. 简化的 DCT 变换（只取 8x8 低频部分）
        let dctSize = 8
        var dctMatrix: [Double] = Array(repeating: 0, count: dctSize * dctSize)
        
        for u in 0..<dctSize {
            for v in 0..<dctSize {
                var sum: Double = 0
                for x in 0..<width {
                    for y in 0..<height {
                        let pixel = grayPixels[y * width + x]
                        sum += pixel *
                            cos(Double((2 * x + 1) * u) * .pi / Double(2 * width)) *
                            cos(Double((2 * y + 1) * v) * .pi / Double(2 * height))
                    }
                }
                let cu = u == 0 ? 1.0 / sqrt(2.0) : 1.0
                let cv = v == 0 ? 1.0 / sqrt(2.0) : 1.0
                dctMatrix[v * dctSize + u] = cu * cv * sum / 4.0
            }
        }
        
        // 4. 计算 DCT 低频部分的均值（排除 DC 分量）
        var lowFreqValues: [Double] = []
        for i in 0..<(dctSize * dctSize) {
            if i != 0 {  // 排除 DC
                lowFreqValues.append(dctMatrix[i])
            }
        }
        
        let mean = lowFreqValues.reduce(0, +) / Double(lowFreqValues.count)
        
        // 5. 与均值比较生成 64-bit 哈希
        var hash: UInt64 = 0
        for (index, value) in dctMatrix.enumerated() {
            if index >= 64 { break }
            if value > mean {
                hash |= (1 << (63 - index))
            }
        }
        
        return hash
    }
    
    // MARK: - 汉明距离
    
    /// 计算两个 64-bit 哈希值的汉明距离
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        var xor = a ^ b
        var distance = 0
        while xor != 0 {
            distance += 1
            xor &= xor - 1  // Brian Kernighan 算法
        }
        return distance
    }
    
    // MARK: - 相似检测
    
    /// 检测相似照片并分组
    func detectSimilar(in photos: [PhotoItem]) -> [SimilarGroup] {
        // 只处理有 pHash 值的照片
        let validPhotos = photos.filter { $0.pHash != nil && $0.asset.mediaType == .image }
        guard validPhotos.count >= SimilarityDetector.minGroupSize else { return [] }
        
        let sortedPhotos = validPhotos.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }

        // 使用并查集（Union-Find）进行聚类。相似废片通常来自连拍/同一场景，按时间窗口比较。
        let uf = UnionFind(sortedPhotos.count)
        
        for i in 0..<sortedPhotos.count {
            let upperBound = min(sortedPhotos.count, i + 1 + SimilarityDetector.maxForwardComparisons)
            guard i + 1 < upperBound else { continue }

            for j in (i + 1)..<upperBound {
                guard let hashA = sortedPhotos[i].pHash,
                      let hashB = sortedPhotos[j].pHash else { continue }
                
                let distance = SimilarityDetector.hammingDistance(hashA, hashB)
                if distance <= SimilarityDetector.hammingThreshold {
                    uf.union(i, j)
                }
            }
        }
        
        // 收集分组
        var groupDict: [Int: [PhotoItem]] = [:]
        for i in 0..<sortedPhotos.count {
            let root = uf.find(i)
            groupDict[root, default: []].append(sortedPhotos[i])
        }
        
        // 过滤 ≥ minGroupSize 的组，按组大小降序
        return groupDict
            .filter { $0.value.count >= SimilarityDetector.minGroupSize }
            .map { SimilarGroup(photos: $0.value) }
            .sorted { $0.photos.count > $1.photos.count }
    }
}

// MARK: - 并查集

private final class UnionFind {
    private var parent: [Int]
    private var rank: [Int]
    
    init(_ n: Int) {
        parent = Array(0..<n)
        rank = Array(repeating: 0, count: n)
    }
    
    func find(_ x: Int) -> Int {
        if parent[x] != x {
            parent[x] = find(parent[x])  // 路径压缩
        }
        return parent[x]
    }
    
    func union(_ x: Int, _ y: Int) {
        let rootX = find(x)
        let rootY = find(y)
        
        if rootX != rootY {
            // 按秩合并
            if rank[rootX] < rank[rootY] {
                parent[rootX] = rootY
            } else if rank[rootX] > rank[rootY] {
                parent[rootY] = rootX
            } else {
                parent[rootY] = rootX
                rank[rootX] += 1
            }
        }
    }
}
