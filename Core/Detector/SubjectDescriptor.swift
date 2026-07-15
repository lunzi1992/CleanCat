import Foundation
import UIKit
import Vision

/// 主体特征描述：人脸区域颜色签名 + 宠物区域颜色签名
/// 用于相似检测时做"同主体"校验，避免把不同人/宠物分到同一相似组
struct SubjectDescriptor {
    /// 人脸区域 4x4 tile 颜色均值（48 维）
    let faceHistogram: [Double]?
    /// 宠物区域 4x4 tile 颜色均值（48 维）
    let petHistogram: [Double]?

    var hasSubject: Bool { faceHistogram != nil || petHistogram != nil }
}

enum SubjectDescriptorExtractor {

    /// 主体直方图余弦相似度阈值：高于此值视为可能同一主体（弱信号，只做拒绝门）
    static let similarityThreshold: Double = 0.75

    /// 从图像中提取主体特征
    static func extract(from image: UIImage) async -> SubjectDescriptor {
        guard let cgImage = image.cgImage else {
            return SubjectDescriptor(faceHistogram: nil, petHistogram: nil)
        }

        // 人脸与动物检测合并到一次 perform 调用，复用 Neural Engine
        let (faceBox, petBox) = await detectSubjects(in: cgImage)
        let faceHistogram = faceBox.flatMap { computeRegionHistogram(cgImage, region: $0) }
        let petHistogram = petBox.flatMap { computeRegionHistogram(cgImage, region: $0) }

        return SubjectDescriptor(faceHistogram: faceHistogram, petHistogram: petHistogram)
    }

    /// 判断两个主体是否相同（或无法判定）
    /// - Returns: true = 相同或无法判定（放行）；false = 明确不同（拒绝分组）
    static func sameSubject(_ lhs: SubjectDescriptor?, _ rhs: SubjectDescriptor?) -> Bool {
        // 任一方无主体信息 → 无法判定，放行（不做过激拒绝）
        guard let lhs, let rhs else { return true }

        // 两方都有人脸 → 比较直方图
        if let lhsFace = lhs.faceHistogram, let rhsFace = rhs.faceHistogram {
            return cosineSimilarity(lhsFace, rhsFace) >= similarityThreshold
        }

        // 一方有人脸、一方有宠物 → 明确不同主体
        if lhs.faceHistogram != nil && rhs.petHistogram != nil { return false }
        if rhs.faceHistogram != nil && lhs.petHistogram != nil { return false }

        // 一方有人脸、另一方什么都没有 → 放行
        if lhs.faceHistogram != nil || rhs.faceHistogram != nil { return true }

        // 两方都只有宠物 → 比较直方图
        if let lhsPet = lhs.petHistogram, let rhsPet = rhs.petHistogram {
            return cosineSimilarity(lhsPet, rhsPet) >= similarityThreshold
        }

        // 两方都没有主体 → 放行
        return true
    }

    // MARK: - 人脸 + 动物检测

    private static func detectSubjects(in cgImage: CGImage) async -> (CGRect?, CGRect?) {
        await withCheckedContinuation { continuation in
            let faceRequest = VNDetectFaceRectanglesRequest()
            let animalRequest = VNRecognizeAnimalsRequest()

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([faceRequest, animalRequest])
            } catch {
                continuation.resume(returning: (nil, nil))
                return
            }

            // 取面积最大的人脸（主体）
            let faceBox = faceRequest.results?
                .max(by: {
                    $0.boundingBox.width * $0.boundingBox.height
                        < $1.boundingBox.width * $1.boundingBox.height
                })?
                .boundingBox

            // 取置信度最高的动物
            let petBox = animalRequest.results?
                .max(by: { $0.confidence < $1.confidence })?
                .boundingBox

            continuation.resume(returning: (faceBox, petBox))
        }
    }

    // MARK: - 区域颜色直方图

    /// 在检测到的主体区域内计算 4x4 tile 颜色均值（48 维）
    private static func computeRegionHistogram(_ cgImage: CGImage, region: CGRect) -> [Double]? {
        let tiles = 4
        let cellSize = 8  // 每个 tile 缩到 8x8
        let width = tiles * cellSize
        let height = tiles * cellSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        // Vision boundingBox 是归一化坐标（原点左下），CGImage 原点左上，需要翻转
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: region.origin.x * imgW,
            y: (1 - region.origin.y - region.height) * imgH,
            width: region.width * imgW,
            height: region.height * imgH
        ).integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var histogram = [Double]()
        histogram.reserveCapacity(tiles * tiles * 3)

        for tileY in 0..<tiles {
            for tileX in 0..<tiles {
                var r: Double = 0
                var g: Double = 0
                var b: Double = 0
                let count = Double(cellSize * cellSize)
                for py in 0..<cellSize {
                    for px in 0..<cellSize {
                        let x = tileX * cellSize + px
                        let y = tileY * cellSize + py
                        let offset = (y * width + x) * bytesPerPixel
                        r += Double(pixels[offset])
                        g += Double(pixels[offset + 1])
                        b += Double(pixels[offset + 2])
                    }
                }
                histogram.append(r / (count * 255))
                histogram.append(g / (count * 255))
                histogram.append(b / (count * 255))
            }
        }

        return histogram
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom == 0 ? 0 : dot / denom
    }
}
