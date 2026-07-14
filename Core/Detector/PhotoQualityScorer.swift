import Foundation
import UIKit
import Vision

/// 照片质量评分器
/// 基于清晰度、曝光、人脸主体、对比度与分辨率做本地评分。
final class PhotoQualityScorer {
    struct Assessment {
        let score: Double
        let reason: String
        let containsFace: Bool
    }

    /// 低质量候选只用于“待检查”，不会触发自动选择或删除。
    struct TechnicalAssessment {
        let score: Double
        let issueReason: String?
    }

    private struct PreparedImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]
        let cgImage: CGImage
    }

    /// 综合质量评分（0-100）。
    static func score(_ image: UIImage) async -> Double {
        await assess(image).score
    }

    static func assess(_ image: UIImage) async -> Assessment {
        guard let prepared = prepare(image) else {
            return Assessment(score: 50, reason: "建议保留", containsFace: false)
        }

        let sharpness = computeSharpness(prepared)
        let exposure = computeExposure(prepared)
        let face = await detectPrimaryFace(in: prepared.cgImage)
        let contrast = computeContrast(prepared)
        let resolution = computeResolutionScore(width: image.size.width * image.scale, height: image.size.height * image.scale)

        let score =
            sharpness.score * 35 +
            exposure.score * 20 +
            face.score * 25 +
            contrast.score * 10 +
            resolution * 10

        let reason = dominantReason([
            (sharpness.score * 35, sharpness.reason),
            (exposure.score * 20, exposure.reason),
            (face.score * 25, face.reason),
            (contrast.score * 10, contrast.reason),
            (resolution * 10, "画面更完整")
        ])

        return Assessment(score: min(100, max(0, score)), reason: reason, containsFace: face.containsFace)
    }

    /// 快速技术质量筛查，不运行人脸识别，供全相册扫描阶段使用。
    static func assessTechnicalQuality(_ image: UIImage) -> TechnicalAssessment {
        guard let prepared = prepare(image, maxDimension: 240) else {
            return TechnicalAssessment(score: 50, issueReason: nil)
        }

        let sharpness = computeSharpness(prepared)
        let exposure = computeExposure(prepared)
        let contrast = computeContrast(prepared)
        let score = (sharpness.score * 55 + exposure.score * 30 + contrast.score * 15) * 100

        // 只收录明显异常，宁可漏掉，也不把普通夜景或氛围照推给用户清理。
        let issueReason: String?
        if exposure.score < 0.20 {
            issueReason = "曝光明显异常"
        } else if sharpness.score < 0.08 && contrast.score < 0.14 && exposure.score > 0.35 {
            issueReason = "画面可能模糊"
        } else {
            issueReason = nil
        }

        return TechnicalAssessment(score: score, issueReason: issueReason)
    }

    private static func prepare(_ image: UIImage, maxDimension: Int = 640) -> PreparedImage? {
        guard let source = image.cgImage else { return nil }

        let scale = min(1, Double(maxDimension) / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale))
        let height = max(1, Int(Double(source.height) * scale))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else { return nil }
        return PreparedImage(width: width, height: height, pixels: pixels, cgImage: cgImage)
    }

    private static func computeSharpness(_ image: PreparedImage) -> (score: Double, reason: String) {
        guard image.width > 2, image.height > 2 else { return (0.5, "建议保留") }

        let step = max(1, min(image.width, image.height) / 180)
        var total: Double = 0
        var count = 0

        for y in stride(from: 1, to: image.height - 1, by: step) {
            for x in stride(from: 1, to: image.width - 1, by: step) {
                let center = grayValue(image, x: x, y: y)
                let top = grayValue(image, x: x, y: y - 1)
                let bottom = grayValue(image, x: x, y: y + 1)
                let left = grayValue(image, x: x - 1, y: y)
                let right = grayValue(image, x: x + 1, y: y)
                total += abs(4 * center - top - bottom - left - right)
                count += 1
            }
        }

        guard count > 0 else { return (0.5, "建议保留") }
        return (min(1, (total / Double(count)) / 70), "更清晰")
    }

    private static func detectPrimaryFace(in cgImage: CGImage) async -> (score: Double, reason: String, containsFace: Bool) {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard error == nil, let faces = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: (0.5, "建议保留", false))
                    return
                }

                guard let face = faces.max(by: {
                    $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
                }) else {
                    continuation.resume(returning: (0.55, "画面更完整", false))
                    return
                }

                let confidence = Double(face.confidence)
                let faceArea = Double(face.boundingBox.width * face.boundingBox.height)
                let sizeScore = min(1, faceArea / 0.24)
                let centerX = Double(face.boundingBox.midX)
                let centerY = Double(face.boundingBox.midY)
                let centerDistance = hypot(centerX - 0.5, centerY - 0.5)
                let centerScore = max(0, 1 - centerDistance / 0.5)
                let yaw = abs(Double(truncating: face.yaw ?? 0))
                let yawScore = max(0, 1 - yaw / 0.8)

                let score = confidence * 0.35 + sizeScore * 0.25 + centerScore * 0.2 + yawScore * 0.2
                continuation.resume(returning: (min(1, max(0, score)), "主体更清楚", true))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: (0.5, "建议保留", false))
            }
        }
    }

    private static func computeExposure(_ image: PreparedImage) -> (score: Double, reason: String) {
        let step = max(1, min(image.width, image.height) / 120)
        var total: Double = 0
        var count = 0

        for y in stride(from: 0, to: image.height, by: step) {
            for x in stride(from: 0, to: image.width, by: step) {
                total += grayValue(image, x: x, y: y) / 255
                count += 1
            }
        }

        guard count > 0 else { return (0.5, "建议保留") }
        let average = total / Double(count)
        let distance = abs(average - 0.52)
        return (max(0, 1 - distance / 0.42), "曝光更稳")
    }

    private static func computeContrast(_ image: PreparedImage) -> (score: Double, reason: String) {
        let step = max(1, min(image.width, image.height) / 120)
        var values: [Double] = []
        values.reserveCapacity((image.width / step + 1) * (image.height / step + 1))

        for y in stride(from: 0, to: image.height, by: step) {
            for x in stride(from: 0, to: image.width, by: step) {
                values.append(grayValue(image, x: x, y: y) / 255)
            }
        }

        guard !values.isEmpty else { return (0.5, "建议保留") }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let contrast = sqrt(variance)
        return (min(1, contrast / 0.28), "层次更好")
    }

    private static func computeResolutionScore(width: CGFloat, height: CGFloat) -> Double {
        let megapixels = Double(width * height) / 1_000_000
        return min(1, megapixels / 8)
    }

    private static func grayValue(_ image: PreparedImage, x: Int, y: Int) -> Double {
        let offset = (y * image.width + x) * 4
        let r = Double(image.pixels[offset])
        let g = Double(image.pixels[offset + 1])
        let b = Double(image.pixels[offset + 2])
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private static func dominantReason(_ weightedReasons: [(Double, String)]) -> String {
        weightedReasons.max(by: { $0.0 < $1.0 })?.1 ?? "建议保留"
    }
}
