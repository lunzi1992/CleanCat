import Foundation
import UIKit
import Vision

/// 照片质量评分器（付费功能）
/// 基于多维度评分：清晰度、人脸检测、曝光
final class PhotoQualityScorer {
    
    /// 综合质量评分（0-100）
    /// - Parameter image: 待评分图片
    /// - Returns: 质量分数，分数越高越好
    static func score(_ image: UIImage) async -> Double {
        var scores: [Double] = []
        
        // 1. 清晰度评分（拉普拉斯方差法）
        let sharpness = computeSharpness(image)
        scores.append(sharpness * 40)  // 权重 40%
        
        // 2. 人脸检测评分
        let faceScore = await detectFaces(in: image)
        scores.append(faceScore * 35)  // 权重 35%
        
        // 3. 曝光评分
        let exposure = computeExposure(image)
        scores.append(exposure * 25)  // 权重 25%
        
        return min(100, max(0, scores.reduce(0, +)))
    }
    
    /// 批量评分
    static func scoreBatch(_ images: [UIImage]) async -> [Double] {
        await withTaskGroup(of: (Int, Double).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let score = await Self.score(image)
                    return (index, score)
                }
            }
            
            var results = Array(repeating: 0.0, count: images.count)
            for await (index, score) in group {
                results[index] = score
            }
            return results
        }
    }
    
    // MARK: - 清晰度（拉普拉斯方差）
    
    private static func computeSharpness(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.5 }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else { return 0.5 }
        
        let data = CFDataGetBytePtr(pixelData)
        let bytesPerPixel = 4
        
        // 降采样以提高性能
        let step = max(1, min(width, height) / 200)
        
        var laplacianSum: Double = 0
        var count = 0
        
        for y in stride(from: 1, to: height - 1, by: step) {
            for x in stride(from: 1, to: width - 1, by: step) {
                let offset = (y * width + x) * bytesPerPixel
                let center = grayValue(data, offset)
                let top = grayValue(data, (y - 1) * width * bytesPerPixel + x * bytesPerPixel)
                let bottom = grayValue(data, (y + 1) * width * bytesPerPixel + x * bytesPerPixel)
                let left = grayValue(data, y * width * bytesPerPixel + (x - 1) * bytesPerPixel)
                let right = grayValue(data, y * width * bytesPerPixel + (x + 1) * bytesPerPixel)
                
                let laplacian = abs(4 * center - top - bottom - left - right)
                laplacianSum += laplacian
                count += 1
            }
        }
        
        guard count > 0 else { return 0.5 }
        let variance = laplacianSum / Double(count)
        
        // 归一化到 0-1
        return min(1.0, variance / 100.0)
    }
    
    private static func grayValue(_ data: UnsafePointer<UInt8>?, _ offset: Int) -> Double {
        guard let data = data else { return 0 }
        let r = Double(data[offset])
        let g = Double(data[offset + 1])
        let b = Double(data[offset + 2])
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
    
    // MARK: - 人脸检测
    
    private static func detectFaces(in image: UIImage) async -> Double {
        guard let cgImage = image.cgImage else { return 0.5 }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: 0.5)
                    return
                }
                
                if results.isEmpty {
                    // 没有人脸不一定不好（风景照等），给中等分
                    continuation.resume(returning: 0.5)
                    return
                }
                
                // 有人脸：检查是否清晰、正面
                var faceScore: Double = 0
                for face in results {
                    // 置信度
                    let confidence = Double(face.confidence)
                    
                    // 人脸大小（太小可能是背景人物）
                    let faceArea = Double(face.boundingBox.width * face.boundingBox.height)
                    let sizeScore = min(1.0, faceArea / 0.3)  // 人脸占画面 30% 满分
                    
                    // 偏航角（yaw）越小越正面
                    let yawAbs = abs(Double(truncating: face.yaw ?? 0))
                    let yawScore = max(0, 1.0 - yawAbs / 45.0)  // 45 度以内有分
                    
                    faceScore = max(faceScore, confidence * 0.4 + sizeScore * 0.3 + yawScore * 0.3)
                }
                
                continuation.resume(returning: faceScore)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    // MARK: - 曝光评分
    
    private static func computeExposure(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.5 }
        
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else { return 0.5 }
        
        let data = CFDataGetBytePtr(pixelData)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        
        // 采样计算平均亮度
        let step = max(1, min(width, height) / 100)
        var totalBrightness: Double = 0
        var count = 0
        
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = (y * width + x) * bytesPerPixel
                totalBrightness += grayValue(data, offset)
                count += 1
            }
        }
        
        guard count > 0 else { return 0.5 }
        let avgBrightness = totalBrightness / Double(count) / 255.0
        
        // 理想曝光在 0.4-0.6 之间（128-153 灰度值）
        // 偏离越远分数越低
        if avgBrightness < 0.4 {
            return avgBrightness / 0.4  // 偏暗
        } else if avgBrightness > 0.6 {
            return (1.0 - avgBrightness) / 0.4  // 偏亮
        } else {
            return 1.0  // 曝光理想
        }
    }
}
