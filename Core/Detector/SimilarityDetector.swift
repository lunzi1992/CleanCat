import Foundation
import UIKit

/// 相似照片检测器
/// 基于感知哈希（pHash）：将图片缩放为 8x8 灰度图，比较汉明距离
final class SimilarityDetector {
    
    /// 汉明距离阈值：≤ 此值的两张照片视为相似
    /// PRD V1.1 REQ-004：遵循"宁可漏判不可误判"原则
    /// 收紧阈值，避免只因天空/云朵等低频结构接近而误分组。
    static let hammingThreshold: Int = 5
    
    /// 最小分组数量：相似组至少需要 2 张照片
    static let minGroupSize: Int = 2

    /// 单张照片最多向后比较的数量。避免大年份相册进入 O(n²) 假死。
    private static let maxForwardComparisons = 40

    /// 相似照片通常来自连拍或同一段拍摄，跨太久宁可不合并。
    private static let maxCaptureTimeGap: TimeInterval = 10 * 60

    /// 平均颜色/饱和度/亮度距离阈值，用来拦截晚霞、蓝天、白云等场景级误判。
    private static let maxColorDistance = 0.18

    /// 宽高比允许轻微裁切差异，但不把横竖构图混成一组。
    private static let maxAspectLogDistance = 0.12
    
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

    static func computeColorSignature(from image: UIImage) -> ColorSignature? {
        guard let cgImage = image.cgImage else { return nil }

        let width = 16
        let height = 16
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard didDraw else { return nil }

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var saturation = 0.0
        var brightness = 0.0
        let pixelCount = Double(width * height)
        var tileSums = [Double](repeating: 0, count: 3 * 3 * 3)
        var tileCounts = [Double](repeating: 0, count: 3 * 3)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                let r = Double(pixels[index]) / 255.0
                let g = Double(pixels[index + 1]) / 255.0
                let b = Double(pixels[index + 2]) / 255.0
                let hsv = rgbToHSV(red: r, green: g, blue: b)
                let tileX = min(2, x * 3 / width)
                let tileY = min(2, y * 3 / height)
                let tileIndex = tileY * 3 + tileX
                let sumIndex = tileIndex * 3

                red += r
                green += g
                blue += b
                saturation += hsv.saturation
                brightness += hsv.brightness
                tileSums[sumIndex] += r
                tileSums[sumIndex + 1] += g
                tileSums[sumIndex + 2] += b
                tileCounts[tileIndex] += 1
            }
        }

        var tileAverages: [Double] = []
        tileAverages.reserveCapacity(tileSums.count)
        for tileIndex in 0..<tileCounts.count {
            let count = max(1, tileCounts[tileIndex])
            let sumIndex = tileIndex * 3
            tileAverages.append(tileSums[sumIndex] / count)
            tileAverages.append(tileSums[sumIndex + 1] / count)
            tileAverages.append(tileSums[sumIndex + 2] / count)
        }

        return ColorSignature(
            red: red / pixelCount,
            green: green / pixelCount,
            blue: blue / pixelCount,
            saturation: saturation / pixelCount,
            brightness: brightness / pixelCount,
            tileAverages: tileAverages
        )
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
        let validPhotos = photos.filter { $0.pHash != nil && $0.asset.mediaType == .image && !$0.isLivePhoto }
        guard validPhotos.count >= SimilarityDetector.minGroupSize else { return [] }
        
        let sortedPhotos = validPhotos.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }

        var adjacency = Array(repeating: Set<Int>(), count: sortedPhotos.count)
        
        for i in 0..<sortedPhotos.count {
            let upperBound = min(sortedPhotos.count, i + 1 + SimilarityDetector.maxForwardComparisons)
            guard i + 1 < upperBound else { continue }

            for j in (i + 1)..<upperBound {
                if let timeGap = captureTimeGap(sortedPhotos[i], sortedPhotos[j]),
                   timeGap > SimilarityDetector.maxCaptureTimeGap {
                    break
                }

                if arePairwiseSimilar(sortedPhotos[i], sortedPhotos[j]) {
                    adjacency[i].insert(j)
                    adjacency[j].insert(i)
                }
            }
        }

        var visited = Set<Int>()
        var groups: [[PhotoItem]] = []

        for index in sortedPhotos.indices where !visited.contains(index) {
            let component = collectComponent(from: index, adjacency: adjacency, visited: &visited)
            guard component.count >= SimilarityDetector.minGroupSize else { continue }

            let componentPhotos = component
                .map { sortedPhotos[$0] }
                .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

            groups.append(contentsOf: splitIntoCoherentGroups(componentPhotos))
        }

        return groups
            .filter { $0.count >= SimilarityDetector.minGroupSize }
            .map { SimilarGroup(photos: $0) }
            .sorted { $0.photos.count > $1.photos.count }
    }

    private static func rgbToHSV(red: Double, green: Double, blue: Double) -> (saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (saturation, maxValue)
    }

    private func arePairwiseSimilar(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        guard let lhsHash = lhs.pHash,
              let rhsHash = rhs.pHash else { return false }

        let hashDistance = SimilarityDetector.hammingDistance(lhsHash, rhsHash)
        guard hashDistance <= SimilarityDetector.hammingThreshold else { return false }
        guard isCaptureTimeClose(lhs, rhs, hashDistance: hashDistance) else { return false }
        guard isAspectRatioClose(lhs, rhs) else { return false }

        if let lhsColor = lhs.colorSignature, let rhsColor = rhs.colorSignature {
            return colorDistance(lhsColor, rhsColor) <= SimilarityDetector.maxColorDistance
        }

        return hashDistance <= 3
    }

    private func isCaptureTimeClose(_ lhs: PhotoItem, _ rhs: PhotoItem, hashDistance: Int) -> Bool {
        guard let gap = captureTimeGap(lhs, rhs) else {
            return hashDistance <= 4
        }
        return gap <= SimilarityDetector.maxCaptureTimeGap
    }

    private func captureTimeGap(_ lhs: PhotoItem, _ rhs: PhotoItem) -> TimeInterval? {
        guard let lhsDate = lhs.creationDate, let rhsDate = rhs.creationDate else { return nil }
        return abs(lhsDate.timeIntervalSince(rhsDate))
    }

    private func isAspectRatioClose(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        guard lhs.pixelWidth > 0, lhs.pixelHeight > 0, rhs.pixelWidth > 0, rhs.pixelHeight > 0 else {
            return true
        }

        let lhsAspect = Double(lhs.pixelWidth) / Double(lhs.pixelHeight)
        let rhsAspect = Double(rhs.pixelWidth) / Double(rhs.pixelHeight)
        return abs(log(lhsAspect / rhsAspect)) <= SimilarityDetector.maxAspectLogDistance
    }

    private func colorDistance(_ lhs: ColorSignature, _ rhs: ColorSignature) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        let saturation = lhs.saturation - rhs.saturation
        let brightness = lhs.brightness - rhs.brightness
        let tileDistance = colorTileDistance(lhs.tileAverages, rhs.tileAverages)

        let globalDistance = sqrt(
            red * red * 0.24 +
            green * green * 0.24 +
            blue * blue * 0.24 +
            saturation * saturation * 0.14 +
            brightness * brightness * 0.14
        )
        return max(globalDistance, tileDistance)
    }

    private func colorTileDistance(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let total = zip(lhs, rhs).reduce(0.0) { partial, pair in
            let delta = pair.0 - pair.1
            return partial + delta * delta
        }
        return sqrt(total / Double(lhs.count))
    }

    private func collectComponent(from start: Int, adjacency: [Set<Int>], visited: inout Set<Int>) -> [Int] {
        var stack = [start]
        var component: [Int] = []
        visited.insert(start)

        while let index = stack.popLast() {
            component.append(index)
            for neighbor in adjacency[index] where !visited.contains(neighbor) {
                visited.insert(neighbor)
                stack.append(neighbor)
            }
        }

        return component
    }

    private func splitIntoCoherentGroups(_ photos: [PhotoItem]) -> [[PhotoItem]] {
        var groups: [[PhotoItem]] = []

        for photo in photos {
            if let groupIndex = groups.firstIndex(where: { group in
                group.allSatisfy { arePairwiseSimilar($0, photo) }
            }) {
                groups[groupIndex].append(photo)
            } else {
                groups.append([photo])
            }
        }

        return groups.filter { $0.count >= SimilarityDetector.minGroupSize }
    }
}
