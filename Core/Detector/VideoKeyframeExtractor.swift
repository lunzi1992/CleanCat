import Foundation
import AVFoundation
import UIKit
import Photos

/// 视频关键帧提取与特征计算
/// 从视频中均匀抽取 N 帧并计算 pHash，供相似检测复用
enum VideoKeyframeExtractor {

    /// 抽取的关键帧数量
    /// 太少会漏掉内容变化，太多会拖慢扫描。4 帧是清晰度与成本的经验平衡点。
    static let keyframeCount = 4

    /// 从 PHAsset 提取关键帧 pHash 数组
    /// - Returns: 关键帧 pHash；视频不可用或抽帧失败时返回空数组
    static func keyframePHashes(for asset: PHAsset) async -> [UInt64] {
        guard let avAsset = await requestAVAsset(for: asset) else { return [] }
        let frames = await extractKeyframes(from: avAsset, count: keyframeCount)
        return frames.map { SimilarityDetector.computePHash(from: $0) }
    }

    /// 提取关键帧图像，供黑帧/低质量视频检测复用
    /// - Parameter count: 关键帧数量；默认 keyframeCount（4 帧）。低质量检测可传 1 仅抽首帧。
    static func keyframeImages(for asset: PHAsset, count: Int = keyframeCount) async -> [UIImage] {
        guard let avAsset = await requestAVAsset(for: asset) else { return [] }
        return await extractKeyframes(from: avAsset, count: count)
    }

    // MARK: - AVAsset 拉取

    private static func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            // 不走网络：iCloud 视频不自动下载原片，与照片策略一致
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    // MARK: - 关键帧抽取

    private static func extractKeyframes(from asset: AVAsset, count: Int) async -> [UIImage] {
        guard let duration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        // 关键帧只用于 pHash（内部再缩到 32x32）和黑帧判定，256 足够
        generator.maximumSize = CGSize(width: 256, height: 256)
        generator.appliesPreferredTrackTransform = true

        var images: [UIImage] = []
        images.reserveCapacity(count)

        // 均匀分布，避开首尾（首帧可能是黑场、尾帧可能是淡出）
        for i in 0..<count {
            let t = totalSeconds * Double(i + 1) / Double(count + 1)
            let cmTime = CMTimeMakeWithSeconds(t, preferredTimescale: 600)
            // copyCGImage 是同步调用，但在 Task 上下文中只阻塞当前任务，可接受
            if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
                images.append(UIImage(cgImage: cgImage))
            }
        }

        return images
    }

    // MARK: - 低质量视频启发式

    /// 判断首帧是否为黑帧（镜头盖/口袋录像典型特征）
    /// - Parameter image: 第一关键帧
    /// - Returns: 平均亮度 < 0.12 视为黑帧
    static func isBlackFrame(_ image: UIImage) -> Bool {
        averageBrightness(of: image) < 0.12
    }

    /// 计算图像平均亮度（0~1）。供黑帧判定与低质量视频启发式复用。
    private static func averageBrightness(of image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 1.0 }

        let width = 32
        let height = 32
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
        ) else { return 1.0 }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total: Double = 0
        let count = width * height
        for i in 0..<count {
            let offset = i * bytesPerPixel
            let r = Double(pixels[offset])
            let g = Double(pixels[offset + 1])
            let b = Double(pixels[offset + 2])
            // 加权灰度，与 pHash 一致
            total += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }

        return total / Double(count)
    }
}
