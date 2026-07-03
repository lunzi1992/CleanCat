import Foundation
import Photos
import UIKit
import CryptoKit

/// 相册扫描引擎
/// 100% 本地处理，照片数据绝不离开设备
/// 支持按年分桶扫描（REQ-014），默认扫描最近一年
@MainActor
final class PhotoScanner: ObservableObject {
    @Published var progress: ScanProgress = .zero
    @Published var state: ScanState = .idle
    @Published var availableYears: [Int] = []
    @Published var yearResults: [YearBucket: ScanResults] = [:]
    @Published var selectedBucket: YearBucket? = nil
    @Published var currentScanLabel: String = ""
    @Published var scanStatusText: String = "准备扫描..."

    private let duplicateDetector = DuplicateDetector()
    private let similarityDetector = SimilarityDetector()
    private let imageManager = PHCachingImageManager()
    private var scanTask: Task<Void, Never>?
    private var activeScanID: UUID?

    /// 全局内存压力观察者（OOM 保护）
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 内存警告：清空所有结果缓存
                self?.yearResults.removeAll()
                self?.imageManager.stopCachingImagesForAllAssets()
            }
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 年份检测

    /// 检测相册中有哪些年份的照片
    func detectAvailableYears() {
        // 复用后台执行,完成后回主线程
        Task.detached(priority: .userInitiated) {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            var years: Set<Int> = []
            let calendar = Calendar.current

            allAssets.enumerateObjects { asset, _, _ in
                if let date = asset.creationDate {
                    years.insert(calendar.component(.year, from: date))
                }
            }

            let sorted = years.sorted(by: >)
            await MainActor.run {
                self.availableYears = sorted
                // 默认选最近一年
                if self.selectedBucket == nil, let first = sorted.first {
                    self.selectedBucket = .year(first)
                }
            }
        }
    }

    // MARK: - 扫描入口

    /// 扫描当前选定的 bucket
    func scanSelected() {
        guard let bucket = selectedBucket else { return }
        if yearResults[bucket] != nil {
            state = .completed
            return
        }
        if case .all = bucket {
            scanAll()
        } else if case .year(let year) = bucket {
            scanYear(year)
        }
    }

    /// 切换年份/全部年份。已有结果直接展示，未扫描过则立即开始扫描。
    func selectBucket(_ bucket: YearBucket, forceRescan: Bool = false) {
        selectedBucket = bucket
        if forceRescan {
            clearResult(for: bucket)
        }

        if yearResults[bucket] != nil, !forceRescan {
            scanTask?.cancel()
            scanTask = nil
            activeScanID = nil
            state = .completed
            progress = .zero
            currentScanLabel = bucket.displayName
            return
        }

        switch bucket {
        case .all:
            scanAll()
        case .year(let year):
            scanYear(year)
        }
    }

    /// 扫描指定年份
    func scanYear(_ year: Int) {
        let scanID = UUID()
        activeScanID = scanID
        state = .scanning
        currentScanLabel = "\(year) 年"
        progress = .zero
        scanStatusText = "准备扫描..."

        let bucket = YearBucket.year(year)
        selectedBucket = bucket

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan(bucket: bucket, scanID: scanID)
        }
    }

    /// 扫描全部年份
    func scanAll() {
        let scanID = UUID()
        activeScanID = scanID
        state = .scanning
        currentScanLabel = "全部年份"
        progress = .zero
        scanStatusText = "准备扫描..."

        let bucket = YearBucket.all
        selectedBucket = bucket

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan(bucket: bucket, scanID: scanID)
        }
    }

    /// 取消扫描
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        activeScanID = nil
        state = .idle
        progress = .zero
        currentScanLabel = ""
        scanStatusText = "准备扫描..."
    }

    /// 清除某个 bucket 的缓存结果
    func clearResult(for bucket: YearBucket) {
        yearResults.removeValue(forKey: bucket)
    }

    func removeDeletedPhotos(_ photoIDs: Set<String>, from bucket: YearBucket? = nil) {
        let target = bucket ?? selectedBucket
        guard let target, let results = yearResults[target] else { return }
        yearResults[target] = results.removing(photoIDs: photoIDs)
    }

    /// 当前选中年份的结果
    var currentResults: ScanResults? {
        guard let bucket = selectedBucket else { return nil }
        return yearResults[bucket]
    }

    /// 是否有任何已扫结果
    var hasAnyResults: Bool {
        !yearResults.isEmpty
    }

    // MARK: - 核心扫描流程

    private func performScan(bucket: YearBucket, scanID: UUID) async {
        let startTime = Date()
        let bucketLabel = bucket.displayName
        AnalyticsManager.shared.track(
            .scanStarted,
            properties: ["bucket": bucketLabel],
            bucket: .medium // 扫描开始时还不知道相册大小,先用 medium
        )

        do {
            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.scanStatusText = "正在读取 \(bucketLabel) 的照片..."
            }

            let assets = try await fetchAssets(bucket: bucket)
            try Task.checkCancellation()
            let total = assets.count
            let sizeBucket = AnalyticsManager.PhotoLibrarySizeBucket.from(total)

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.progress = ScanProgress(current: 0, total: total)
            }

            if total == 0 {
                await MainActor.run {
                    guard self.isActiveScan(scanID) else { return }
                    let empty = ScanResults(
                        totalPhotoCount: 0,
                        duplicateGroups: [],
                        similarGroups: [],
                        screenshots: [],
                        screenRecordings: [],
                        scanDuration: 0
                    )
                    self.yearResults[bucket] = empty
                    self.state = .completed
                }
                AnalyticsManager.shared.track(
                    .scanCompleted,
                    properties: ["bucket": bucketLabel, "photo_count": 0, "duration_ms": 0],
                    bucket: .empty
                )
                return
            }

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.scanStatusText = "正在分析照片特征..."
            }
            var photos = await processAssetsConcurrently(assets: assets, bucket: bucket, scanID: scanID)

            try Task.checkCancellation()

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.scanStatusText = "正在确认重复照片..."
            }

            photos = await enrichFileHashesForDuplicateCandidates(in: photos)
            try Task.checkCancellation()

            let duplicateGroups = await Task.detached(priority: .userInitiated) {
                DuplicateDetector().detectDuplicates(in: photos)
            }.value
            try Task.checkCancellation()

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.scanStatusText = "正在生成整理结果..."
            }

            var similarGroups = await Task.detached(priority: .userInitiated) {
                SimilarityDetector().detectSimilar(in: photos)
            }.value
            try Task.checkCancellation()

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.scanStatusText = "正在评估建议保留照片..."
            }

            similarGroups = await applyQualityScores(in: similarGroups, scanID: scanID)

            // 阶段 6: 截图与录屏分类
            let screenshots = photos.filter { $0.isScreenshot }
            let recordings = photos.filter { $0.isScreenRecording }

            let duration = Date().timeIntervalSince(startTime)
            let results = ScanResults(
                totalPhotoCount: total,
                duplicateGroups: duplicateGroups,
                similarGroups: similarGroups,
                screenshots: screenshots,
                screenRecordings: recordings,
                scanDuration: duration
            )

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.yearResults[bucket] = results
                self.state = .completed
                self.scanStatusText = "整理完成"
                self.activeScanID = nil
            }

            AnalyticsManager.shared.track(
                .scanCompleted,
                properties: [
                    "bucket": bucketLabel,
                    "photo_count": total,
                    "duration_ms": Int(duration * 1000),
                    "duplicate_groups": duplicateGroups.count,
                    "similar_groups": similarGroups.count,
                    "screenshots": screenshots.count
                ],
                bucket: sizeBucket
            )
        } catch is CancellationError {
            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.state = .idle
                self.activeScanID = nil
            }
            AnalyticsManager.shared.track(.scanCancelled, properties: ["bucket": bucketLabel])
        } catch {
            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.state = .error(error.localizedDescription)
                self.activeScanID = nil
            }
            AnalyticsManager.shared.track(
                .scanFailed,
                properties: ["bucket": bucketLabel, "error": error.localizedDescription]
            )
        }
    }

    private func isActiveScan(_ scanID: UUID) -> Bool {
        activeScanID == scanID
    }

    // MARK: - 资源拉取

    private func fetchAssets(bucket: YearBucket) async throws -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false

        if case .year(let year) = bucket {
            let calendar = Calendar.current
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            fetchOptions.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                yearStart as NSDate,
                yearEnd as NSDate
            )
        }

        let imageAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let videoAssets = PHAsset.fetchAssets(with: .video, options: fetchOptions)

        var all: [PHAsset] = []
        all.reserveCapacity(imageAssets.count + videoAssets.count)
        imageAssets.enumerateObjects { asset, _, _ in all.append(asset) }
        videoAssets.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.videoScreenRecording) {
                all.append(asset)
            }
        }
        return all
    }

    // MARK: - 并发处理（pHash + MD5 + 元数据）

    private func processAssetsConcurrently(assets: [PHAsset], bucket: YearBucket, scanID: UUID) async -> [PhotoItem] {
        // 并发限流：iPhone 16 Pro Max 4 核性能级,4 并发 + 缩略图策略避免 OOM
        let maxConcurrent = 4
        let total = assets.count
        var processed: [PhotoItem] = []
        processed.reserveCapacity(total)

        await withTaskGroup(of: (Int, PhotoItem?).self) { group in
            var iterator = assets.makeIterator()
            var inFlight = 0
            var index = 0

            // 启动首批任务
            while inFlight < maxConcurrent, let asset = iterator.next() {
                let currentIndex = index
                index += 1
                inFlight += 1
                group.addTask { [weak self] in
                    guard let self = self else { return (currentIndex, nil) }
                    let item = await self.processOneAsset(asset)
                    return (currentIndex, item)
                }
            }

            // 持续消费结果,并保持流水线满载
            for await (i, item) in group {
                if Task.isCancelled || !isActiveScan(scanID) {
                    group.cancelAll()
                    break
                }

                inFlight -= 1
                if let item = item {
                    processed.append(item)
                }

                // 进度节流:每 20 张或最后一张更新
                if i % 20 == 0 || i == total - 1 {
                    let snapshot = processed.count
                    await MainActor.run {
                        guard self.isActiveScan(scanID) else { return }
                        self.progress = ScanProgress(current: snapshot, total: total)
                    }
                }

                // 启动下一个任务填满流水线
                if let asset = iterator.next() {
                    let currentIndex = index
                    index += 1
                    inFlight += 1
                    group.addTask { [weak self] in
                        guard let self = self else { return (currentIndex, nil) }
                        let item = await self.processOneAsset(asset)
                        return (currentIndex, item)
                    }
                }
            }
        }

        return processed
    }

    /// 处理单张照片:pHash + MD5 + 元数据
    private nonisolated func processOneAsset(_ asset: PHAsset) async -> PhotoItem {
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let isScreenRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
        let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)

        let resources = PHAssetResource.assetResources(for: asset)
        let fileSize = resources.first?.value(forKey: "fileSize") as? Int64 ?? 0

        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .exact
        options.isSynchronous = false

        let thumb = await requestThumbnail(asset: asset, size: CGSize(width: 256, height: 256), imageManager: imageManager, options: options)

        var pHashValue: UInt64? = nil
        var colorSignature: ColorSignature? = nil

        if let img = thumb {
            pHashValue = SimilarityDetector.computePHash(from: img)
            colorSignature = SimilarityDetector.computeColorSignature(from: img)
        }

        return PhotoItem(
            id: asset.localIdentifier,
            asset: asset,
            md5Hash: nil,
            pHash: pHashValue,
            isScreenshot: isScreenshot,
            isScreenRecording: isScreenRecording,
            isLivePhoto: isLivePhoto,
            fileSize: fileSize,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            colorSignature: colorSignature,
            qualityScore: nil,
            qualityReason: nil
        )
    }

    private func enrichFileHashesForDuplicateCandidates(in photos: [PhotoItem]) async -> [PhotoItem] {
        let candidates = duplicateCandidateIDs(in: photos)
        guard !candidates.isEmpty else { return photos }

        let hashMap = await computeFileHashes(for: photos.filter { candidates.contains($0.id) })
        guard !hashMap.isEmpty else { return photos }

        return photos.map { photo in
            var updated = photo
            updated.md5Hash = hashMap[photo.id]
            return updated
        }
    }

    private func duplicateCandidateIDs(in photos: [PhotoItem]) -> Set<String> {
        let grouped = Dictionary(grouping: photos.filter { $0.asset.mediaType == .image && !$0.isLivePhoto && $0.fileSize > 0 }) { photo in
            "\(photo.fileSize)-\(photo.pixelWidth)x\(photo.pixelHeight)"
        }

        return Set(
            grouped.values
                .filter { $0.count >= 2 }
                .flatMap { $0.map(\.id) }
        )
    }

    private func computeFileHashes(for photos: [PhotoItem]) async -> [String: String] {
        let maxConcurrent = 2
        var result: [String: String] = [:]

        await withTaskGroup(of: (String, String?).self) { group in
            var iterator = photos.makeIterator()
            var inFlight = 0

            while inFlight < maxConcurrent, let photo = iterator.next() {
                inFlight += 1
                group.addTask { [weak self] in
                    guard let self = self else { return (photo.id, nil) }
                    return (photo.id, await self.requestFileMD5(for: photo.asset))
                }
            }

            for await (id, hash) in group {
                inFlight -= 1
                if let hash {
                    result[id] = hash
                }

                if let photo = iterator.next() {
                    inFlight += 1
                    group.addTask { [weak self] in
                        guard let self = self else { return (photo.id, nil) }
                        return (photo.id, await self.requestFileMD5(for: photo.asset))
                    }
                }
            }
        }

        return result
    }

    private nonisolated func requestThumbnail(asset: PHAsset, size: CGSize, imageManager: PHImageManager, options: PHImageRequestOptions) async -> UIImage? {
        await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private nonisolated func requestFileMD5(for asset: PHAsset) async -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first else {
            return nil
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            var hasher = Insecure.MD5()
            let lock = NSLock()
            var didResume = false

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    lock.lock()
                    hasher.update(data: data)
                    lock.unlock()
                },
                completionHandler: { error in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true

                    if error != nil {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: MD5Hash.hexString(from: hasher.finalize()))
                    }
                }
            )
        }
    }

    // MARK: - 建议保留评分

    private func applyQualityScores(in groups: [SimilarGroup], scanID: UUID) async -> [SimilarGroup] {
        let assessments = await computeQualityAssessments(for: groups.flatMap(\.photos), scanID: scanID)

        return groups.map { group in
            let enriched = group.photos.map { photo -> PhotoItem in
                var updated = photo
                if let assessment = assessments[photo.id] {
                    updated.qualityScore = assessment.score
                    updated.qualityReason = assessment.reason
                    updated.containsFace = assessment.containsFace
                } else {
                    updated.qualityScore = fallbackQualityScore(for: photo)
                    updated.qualityReason = "建议保留"
                    updated.containsFace = false
                }
                return updated
            }
            return SimilarGroup(photos: enriched)
        }
    }

    private func computeQualityAssessments(for photos: [PhotoItem], scanID: UUID) async -> [String: PhotoQualityScorer.Assessment] {
        let uniquePhotos = Array(Dictionary(grouping: photos, by: \.id).compactMap { $0.value.first })
        let maxConcurrent = 2
        var result: [String: PhotoQualityScorer.Assessment] = [:]

        await withTaskGroup(of: (String, PhotoQualityScorer.Assessment?).self) { group in
            var iterator = uniquePhotos.makeIterator()
            var inFlight = 0

            while inFlight < maxConcurrent, let photo = iterator.next() {
                inFlight += 1
                group.addTask { [weak self] in
                    guard let self else { return (photo.id, nil) }
                    guard let image = await self.requestQualityImage(for: photo.asset) else {
                        return (photo.id, nil)
                    }
                    return (photo.id, await PhotoQualityScorer.assess(image))
                }
            }

            for await (id, assessment) in group {
                inFlight -= 1

                if Task.isCancelled || !isActiveScan(scanID) {
                    group.cancelAll()
                    break
                }

                if let assessment {
                    result[id] = assessment
                }

                if let photo = iterator.next() {
                    inFlight += 1
                    group.addTask { [weak self] in
                        guard let self else { return (photo.id, nil) }
                        guard let image = await self.requestQualityImage(for: photo.asset) else {
                            return (photo.id, nil)
                        }
                        return (photo.id, await PhotoQualityScorer.assess(image))
                    }
                }
            }
        }

        return result
    }

    private nonisolated func requestQualityImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        let longestSide = max(asset.pixelWidth, asset.pixelHeight)
        let scale = longestSide > 0 ? min(1, 900 / CGFloat(longestSide)) : 1
        let targetSize = CGSize(
            width: max(320, CGFloat(asset.pixelWidth) * scale),
            height: max(320, CGFloat(asset.pixelHeight) * scale)
        )

        return await withCheckedContinuation { continuation in
            let stateQueue = DispatchQueue(label: "cleancat.quality-image-request")
            var didResume = false
            var requestID: PHImageRequestID?

            func resume(_ image: UIImage?) {
                let shouldResume = stateQueue.sync { () -> Bool in
                    guard !didResume else { return false }
                    didResume = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: image)
                }
            }

            requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    return
                }
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                    return
                }
                resume(image)
            }

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let (shouldCancel, id) = stateQueue.sync {
                    (!didResume, requestID)
                }
                if shouldCancel {
                    if let id {
                        PHImageManager.default().cancelImageRequest(id)
                    }
                    resume(nil)
                }
            }
        }
    }

    private func fallbackQualityScore(for photo: PhotoItem) -> Double {
        let megapixels = Double(photo.pixelWidth * photo.pixelHeight) / 1_000_000
        let resolutionScore = min(45, megapixels * 5)

        let fileSizeMB = Double(photo.fileSize) / 1_048_576
        let fileScore = min(25, fileSizeMB * 3)

        let aspect = photo.pixelHeight == 0 ? 1 : Double(photo.pixelWidth) / Double(photo.pixelHeight)
        let aspectScore = (0.45...2.4).contains(aspect) ? 15.0 : 8.0

        let dateScore = photo.creationDate == nil ? 5.0 : 15.0
        return min(100, resolutionScore + fileScore + aspectScore + dateScore)
    }
}

// MARK: - 年份分桶枚举

enum YearBucket: Hashable {
    case year(Int)
    case all

    var displayName: String {
        switch self {
        case .year(let y): return "\(y) 年"
        case .all: return "全部"
        }
    }

    var isAll: Bool {
        if case .all = self { return true }
        return false
    }
}

// MARK: - Array 扩展

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
