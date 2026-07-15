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
    private var pausedBucket: YearBucket?

    /// 视频相似深度扫描开关。
    /// 关闭时：视频不抽帧、不计算 pHash/主体，也不参与相似检测；完全重复仍通过文件哈希确认。
    /// 开启时：视频抽 4 帧 + pHash + 主体特征，参与相似检测（成本高，大相册可能卡顿）。
    /// MVP 默认关闭，保证扫描稳定；后续可暴露为用户可切换的设置项。
    nonisolated static let enableVideoSimilarityScan = false
    /// 每次扫描最多精检的相似候选。其余组降为“谨慎检查”，不进入批量建议。
    /// 固定预算让按年份与全量扫描的尾处理耗时都可控。
    nonisolated private static let maxSubjectValidationPhotos = 96

    /// 全局内存压力观察者（OOM 保护）
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 扫描结果只保存轻量特征和 PHAsset 引用，保留它们才能在前后台切换后继续展示。
                // 内存压力下仅释放 PhotoKit 的图片缓存。
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
        pausedBucket = nil
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
        pausedBucket = nil
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
        pausedBucket = nil
        state = .idle
        progress = .zero
        currentScanLabel = ""
        scanStatusText = "准备扫描..."
    }

    /// iOS 在后台不保证相册请求继续执行。主动取消当前批次，回到前台后从该年份重新开始，
    /// 避免半截扫描继续占用资源或留下不完整结果。
    func pauseForBackground() {
        guard case .scanning = state, let bucket = selectedBucket else { return }

        pausedBucket = bucket
        scanTask?.cancel()
        scanTask = nil
        activeScanID = nil
        state = .idle
        progress = .zero
        scanStatusText = "扫描已暂停"
        AnalyticsManager.shared.track(.scanPaused, properties: ["bucket": bucket.displayName])
    }

    func resumeAfterForeground() {
        guard let bucket = pausedBucket else { return }
        pausedBucket = nil
        AnalyticsManager.shared.track(.scanResumed, properties: ["bucket": bucket.displayName])
        selectBucket(bucket, forceRescan: true)
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
                        lowQualityPhotos: [],
                        cloudOnlyPhotoCount: 0,
                        livePhotoCount: 0,
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

            // 主体特征按固定预算惰性提取。精检完成的组才可能成为“高可信”；
            // 超出预算或图片不可用的组保留为“谨慎检查”，避免尾处理时间随年份照片量失控。
            let similarCandidateCount = Set(similarGroups.flatMap { $0.photos.map(\.id) }).count
            if similarCandidateCount > 0 {
                await MainActor.run {
                    guard self.isActiveScan(scanID) else { return }
                    self.scanStatusText = "正在校验相似照片主体..."
                }
                photos = await enrichSubjectDescriptors(in: photos, similarGroups: similarGroups, scanID: scanID)
                try Task.checkCancellation()
                similarGroups = await Task.detached(priority: .userInitiated) {
                    SimilarityDetector().detectSimilar(in: photos)
                }.value
            }

            await MainActor.run {
                guard self.isActiveScan(scanID) else { return }
                self.scanStatusText = "正在评估建议保留照片..."
            }

            // 清晰度、曝光、对比度已在首次拉图时计算；这里直接复用，避免再次请求图片和跑 Vision。
            similarGroups = groupsWithScanQuality(similarGroups)

            // 阶段 6: 截图与录屏分类
            let screenshots = photos.filter { $0.isScreenshot }
            let recordings = photos.filter { $0.isScreenRecording }
            let lowQualityPhotos = photos.filter {
                $0.qualityIssueReason != nil &&
                !$0.isScreenshot &&
                !$0.isScreenRecording &&
                !$0.isLivePhoto &&
                !$0.isCloudOnly &&
                !$0.asset.isFavorite
            }
            let cloudOnlyPhotoCount = photos.filter(\.isCloudOnly).count
            let livePhotoCount = photos.filter(\.isLivePhoto).count

            let duration = Date().timeIntervalSince(startTime)
            let results = ScanResults(
                totalPhotoCount: total,
                duplicateGroups: duplicateGroups,
                similarGroups: similarGroups,
                screenshots: screenshots,
                screenRecordings: recordings,
                lowQualityPhotos: lowQualityPhotos,
                cloudOnlyPhotoCount: cloudOnlyPhotoCount,
                livePhotoCount: livePhotoCount,
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
                    "screenshots": screenshots.count,
                    "low_quality_photos": lowQualityPhotos.count,
                    "cloud_only_photos": cloudOnlyPhotoCount,
                    "live_photos": livePhotoCount
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
        // 视频全量纳入：普通视频参与重复/相似/低质量检测，录屏仍归入截图桶
        videoAssets.enumerateObjects { asset, _, _ in all.append(asset) }
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
            var completedCount = 0
            for await (_, item) in group {
                if Task.isCancelled || !isActiveScan(scanID) {
                    group.cancelAll()
                    break
                }

                inFlight -= 1
                completedCount += 1
                if let item = item {
                    processed.append(item)
                }

                // 进度节流:每 20 张或最后一张更新
                if completedCount % 20 == 0 || completedCount == total {
                    let snapshot = completedCount
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

    /// 处理单个资源：照片走 pHash + 质量评分；视频走关键帧 pHash + 低质量启发式
    private nonisolated func processOneAsset(_ asset: PHAsset) async -> PhotoItem {
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let isScreenRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
        let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        let isVideoAsset = asset.mediaType == .video && !isLivePhoto

        let resources = PHAssetResource.assetResources(for: asset)
        let fileSize = resources.first?.value(forKey: "fileSize") as? Int64 ?? 0

        // 照片路径
        if !isVideoAsset {
            let analysisImage = asset.mediaType == .image ? await requestQualityImage(for: asset) : nil
            let isCloudOnly = asset.mediaType == .image && analysisImage == nil

            var pHashValue: UInt64? = nil
            var colorSignature: ColorSignature? = nil
            var technicalQualityScore: Double? = nil
            var qualityIssueReason: String? = nil
            var screenshotCat: ScreenshotCategory? = nil
            var livePhotoVideoPHash: UInt64? = nil

            if let img = analysisImage {
                pHashValue = SimilarityDetector.computePHash(from: img)
                colorSignature = SimilarityDetector.computeColorSignature(from: img)
                let technicalAssessment = PhotoQualityScorer.assessTechnicalQuality(img)
                technicalQualityScore = technicalAssessment.score
                qualityIssueReason = technicalAssessment.issueReason
                // 截图做内容分类（OCR + 规则匹配）
                if isScreenshot {
                    screenshotCat = await ScreenshotClassifier.classify(
                        image: img,
                        creationDate: asset.creationDate
                    )
                }
            }

            // Live Photo 视频部分：抽首帧 pHash，参与相似检测
            // 让 Live Photo 能与同场景的普通视频/照片相互命中
            if isLivePhoto, !isCloudOnly {
                let keyframes = await VideoKeyframeExtractor.keyframeImages(for: asset, count: 1)
                if let firstFrame = keyframes.first {
                    livePhotoVideoPHash = SimilarityDetector.computePHash(from: firstFrame)
                }
            }

            // 主体特征不在此处全量提取：7000 张全量跑 Vision 主体检测会拖慢扫描 1-2 分钟。
            // 改为在相似检测分组后，只对相似组内照片提取（通常几百张），成本降一个数量级。
            return PhotoItem(
                id: asset.localIdentifier,
                asset: asset,
                md5Hash: nil,
                pHash: pHashValue,
                isScreenshot: isScreenshot,
                isScreenRecording: isScreenRecording,
                isLivePhoto: isLivePhoto,
                isCloudOnly: isCloudOnly,
                fileSize: fileSize,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                colorSignature: colorSignature,
                qualityScore: nil,
                qualityReason: nil,
                technicalQualityScore: technicalQualityScore,
                qualityIssueReason: qualityIssueReason,
                containsFace: false,
                subjectDescriptor: nil,
                screenshotCategory: screenshotCat,
                livePhotoVideoPHash: livePhotoVideoPHash
            )
        }

        // 视频路径：深度扫描关闭时不做全量抽帧，重复视频仍通过 MD5 候选确认。
        // 抽帧主要服务视频相似和黑帧判断，MVP 默认关闭以保证大相册扫描速度。
        let deepScan = PhotoScanner.enableVideoSimilarityScan
        let keyframes = deepScan
            ? await VideoKeyframeExtractor.keyframeImages(for: asset, count: VideoKeyframeExtractor.keyframeCount)
            : []
        let isCloudOnly = deepScan && keyframes.isEmpty
        let duration = asset.duration > 0 ? asset.duration : nil

        // pHash + 主体特征仅在深度扫描开启时计算
        var keyframePHashes: [UInt64] = []
        var subjectDesc: SubjectDescriptor? = nil
        var hasFace = false
        if deepScan {
            keyframePHashes = keyframes.map { SimilarityDetector.computePHash(from: $0) }
            if let firstFrame = keyframes.first {
                subjectDesc = await SubjectDescriptorExtractor.extract(from: firstFrame)
                hasFace = subjectDesc?.faceHistogram != nil
            }
        }

        var qualityIssueReason: String? = nil
        if !isCloudOnly && !isScreenRecording {
            // 低质量视频启发式：口袋录像 / 镜头盖 / 低分辨率
            if let duration, duration < 3 {
                if let firstFrame = keyframes.first, VideoKeyframeExtractor.isBlackFrame(firstFrame) {
                    qualityIssueReason = "疑似镜头盖或口袋录像"
                } else {
                    qualityIssueReason = "视频过短（<3秒）"
                }
            } else if asset.pixelWidth < 480 || asset.pixelHeight < 480 {
                qualityIssueReason = "视频分辨率过低"
            }
        }

        return PhotoItem(
            id: asset.localIdentifier,
            asset: asset,
            md5Hash: nil,
            pHash: nil,
            isScreenshot: isScreenshot,
            isScreenRecording: isScreenRecording,
            isLivePhoto: isLivePhoto,
            isCloudOnly: isCloudOnly,
            fileSize: fileSize,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            colorSignature: nil,
            qualityScore: nil,
            qualityReason: nil,
            technicalQualityScore: nil,
            qualityIssueReason: qualityIssueReason,
            containsFace: hasFace,
            keyframePHashes: keyframePHashes,
            videoDuration: duration,
            isVideo: true,
            subjectDescriptor: subjectDesc
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

    /// 只对预算内的完整相似组提取主体特征。不会截断一个组，保证高可信组内每张都完成校验。
    private func enrichSubjectDescriptors(in photos: [PhotoItem], similarGroups: [SimilarGroup], scanID: UUID) async -> [PhotoItem] {
        let candidateIDs = subjectValidationCandidateIDs(in: similarGroups)
        guard !candidateIDs.isEmpty else { return photos }

        let candidates = photos.filter { candidateIDs.contains($0.id) }
        let resultMap = await computeSubjectDescriptors(for: candidates, scanID: scanID)

        return photos.map { photo in
            guard let bundle = resultMap[photo.id] else { return photo }
            var updated = photo
            updated.subjectDescriptor = bundle.descriptor
            updated.containsFace = bundle.descriptor?.faceHistogram != nil
            updated.subjectAssessmentCompleted = bundle.completed
            return updated
        }
    }

    private func subjectValidationCandidateIDs(in groups: [SimilarGroup]) -> Set<String> {
        var selected = Set<String>()

        for group in groups {
            let groupIDs = Set(group.photos.map(\.id))
            let additionalCount = groupIDs.subtracting(selected).count
            guard selected.count + additionalCount <= PhotoScanner.maxSubjectValidationPhotos else { continue }
            selected.formUnion(groupIDs)
        }

        return selected
    }

    private struct SubjectDescriptorBundle {
        let descriptor: SubjectDescriptor?
        let completed: Bool
    }

    private func computeSubjectDescriptors(for photos: [PhotoItem], scanID: UUID) async -> [String: SubjectDescriptorBundle] {
        let maxConcurrent = 4
        var result: [String: SubjectDescriptorBundle] = [:]

        await withTaskGroup(of: (String, SubjectDescriptorBundle).self) { group in
            var iterator = photos.makeIterator()
            var inFlight = 0

            while inFlight < maxConcurrent, let photo = iterator.next() {
                inFlight += 1
                group.addTask { [weak self] in
                    guard let self else { return (photo.id, SubjectDescriptorBundle(descriptor: nil, completed: false)) }
                    guard let image = await self.requestSubjectImage(for: photo.asset) else {
                        return (photo.id, SubjectDescriptorBundle(descriptor: nil, completed: false))
                    }
                    let descriptor = await SubjectDescriptorExtractor.extract(from: image)
                    return (photo.id, SubjectDescriptorBundle(descriptor: descriptor, completed: true))
                }
            }

            for await (id, bundle) in group {
                if Task.isCancelled || !isActiveScan(scanID) {
                    group.cancelAll()
                    break
                }
                inFlight -= 1
                result[id] = bundle

                if let photo = iterator.next() {
                    inFlight += 1
                    group.addTask { [weak self] in
                        guard let self else { return (photo.id, SubjectDescriptorBundle(descriptor: nil, completed: false)) }
                        guard let image = await self.requestSubjectImage(for: photo.asset) else {
                            return (photo.id, SubjectDescriptorBundle(descriptor: nil, completed: false))
                        }
                        let descriptor = await SubjectDescriptorExtractor.extract(from: image)
                        return (photo.id, SubjectDescriptorBundle(descriptor: descriptor, completed: true))
                    }
                }
            }
        }

        return result
    }

    private func duplicateCandidateIDs(in photos: [PhotoItem]) -> Set<String> {
        // 媒体类型 + fileSize + 尺寸预筛，避免照片/视频/Live Photo 互相触发无效 MD5 读取。
        let grouped = Dictionary(grouping: photos.filter { !$0.isCloudOnly && $0.fileSize > 0 }) { photo in
            "\(duplicateMediaKind(for: photo))-\(photo.fileSize)-\(photo.pixelWidth)x\(photo.pixelHeight)"
        }

        return Set(
            grouped.values
                .filter { $0.count >= 2 }
                .flatMap { $0.map(\.id) }
        )
    }

    private func duplicateMediaKind(for photo: PhotoItem) -> String {
        if photo.isVideo { return "video" }
        if photo.isLivePhoto { return "live" }
        return "photo"
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

    private nonisolated func requestFileMD5(for asset: PHAsset) async -> String? {
        let resources = PHAssetResource.assetResources(for: asset)

        if asset.mediaType == .video {
            // 普通视频：只用 .video / .fullSizeVideo 资源，不 fallback 到封面图
            // 加 "v:" 前缀隔离 hash 空间，避免视频封面 MD5 和照片撞车导致跨类型误判
            guard let resource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) else {
                return nil
            }
            guard let md5 = await computeResourceMD5(resource) else { return nil }
            return "v:\(md5)"
        } else if asset.mediaSubtypes.contains(.photoLive) {
            // Live Photo：静态照 + paired video 都计算，组合 hash
            // 只有两者都相同才视为完全重复（保守，避免静态照相同但视频不同的误判）
            let photoResource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto })
            let videoResource = resources.first(where: { $0.type == .pairedVideo })

            let p: String? = photoResource != nil ? await computeResourceMD5(photoResource!) : nil
            let v: String? = videoResource != nil ? await computeResourceMD5(videoResource!) : nil

            if let p, let v {
                return "lp:\(p)|\(v)"
            } else if let p {
                return "lp:\(p)"
            } else {
                return v.map { "lp:\($0)" }
            }
        } else {
            // 普通照片：加 "p:" 前缀，与视频 hash 空间隔离
            guard let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first else {
                return nil
            }
            guard let md5 = await computeResourceMD5(resource) else { return nil }
            return "p:\(md5)"
        }
    }

    private nonisolated func computeResourceMD5(_ resource: PHAssetResource) async -> String? {
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

    private func groupsWithScanQuality(_ groups: [SimilarGroup]) -> [SimilarGroup] {
        groups.map { group in
            let enriched = group.photos.map { photo -> PhotoItem in
                guard photo.qualityScore == nil else { return photo }
                var updated = photo
                updated.qualityScore = fallbackQualityScore(for: photo)
                updated.qualityReason = recommendationReason(for: updated)
                return updated
            }
            return SimilarGroup(photos: enriched)
        }
    }

    private func recommendationReason(for photo: PhotoItem) -> String {
        if photo.asset.isFavorite { return "已收藏，建议保留" }
        if photo.containsFace { return "含人脸，建议保留" }
        if photo.technicalQualityScore ?? 0 >= 72 { return "画面质量较好，建议保留" }
        return "建议保留"
    }

    private nonisolated func requestQualityImage(for asset: PHAsset) async -> UIImage? {
        let needsOCRDetail = asset.mediaSubtypes.contains(.photoScreenshot)
        return await requestAnalysisImage(
            for: asset,
            maxDimension: needsOCRDetail ? 900 : 480,
            deliveryMode: .highQualityFormat,
            acceptsDegradedImage: false,
            timeoutNanoseconds: 2_000_000_000
        )
    }

    private nonisolated func requestSubjectImage(for asset: PHAsset) async -> UIImage? {
        await requestAnalysisImage(
            for: asset,
            maxDimension: 480,
            deliveryMode: .fastFormat,
            acceptsDegradedImage: true,
            timeoutNanoseconds: 750_000_000
        )
    }

    private nonisolated func requestAnalysisImage(
        for asset: PHAsset,
        maxDimension: CGFloat,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        acceptsDegradedImage: Bool,
        timeoutNanoseconds: UInt64
    ) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        let longestSide = max(asset.pixelWidth, asset.pixelHeight)
        let scale = longestSide > 0 ? min(1, maxDimension / CGFloat(longestSide)) : 1
        let targetSize = CGSize(
            width: max(1, CGFloat(asset.pixelWidth) * scale),
            height: max(1, CGFloat(asset.pixelHeight) * scale)
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
                if let inCloud = info?[PHImageResultIsInCloudKey] as? Bool, inCloud {
                    resume(nil)
                    return
                }
                if !acceptsDegradedImage,
                   let degraded = info?[PHImageResultIsDegradedKey] as? Bool,
                   degraded {
                    return
                }
                resume(image)
            }

            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
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
        let technicalScore = min(100, max(0, photo.technicalQualityScore ?? 50)) * 0.72

        let megapixels = Double(photo.pixelWidth * photo.pixelHeight) / 1_000_000
        let resolutionScore = min(12, megapixels * 1.5)

        let fileSizeMB = Double(photo.fileSize) / 1_048_576
        let fileScore = min(4, fileSizeMB * 0.8)

        let favoriteScore = photo.asset.isFavorite ? 12.0 : 0
        return min(100, technicalScore + resolutionScore + fileScore + favoriteScore)
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
