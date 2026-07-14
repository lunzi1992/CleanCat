import SwiftUI

/// 扫描结果展示页(三 Tab,奶油白配色)
struct ResultsView: View {
    let results: ScanResults
    @ObservedObject var scanner: PhotoScanner
    @State private var selectedTab: ResultTab = .duplicates
    @State private var showDeleteConfirm = false
    @State private var selectedPhotos: Set<String> = []
    @State private var cleanupSummary: CleanupSummary?

    enum ResultTab: String, CaseIterable {
        case duplicates = "重复照片"
        case similar = "相似照片"
        case screenshots = "截图"
        case lowQuality = "待检查"

        var icon: String {
            switch self {
            case .duplicates: return "doc.on.doc"
            case .similar: return "rectangle.3.group"
            case .screenshots: return "camera.viewfinder"
            case .lowQuality: return "exclamationmark.triangle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            yearSelector
            tabSelector
            contentView
                .padding(.bottom, 100)
            if !selectedPhotos.isEmpty {
                bottomActionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.cream.ignoresSafeArea())
        .onAppear {
            AnalyticsManager.shared.track(
                .resultPageViewed,
                properties: [
                    "duplicate_groups": results.duplicateGroups.count,
                    "similar_groups": results.similarGroups.count,
                    "screenshots": results.screenshots.count,
                    "low_quality_photos": results.lowQualityPhotos.count
                ]
            )
        }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteConfirmView(
                photos: selectedPhotoItems()
            ) { result in
                handleDeleteResult(result)
            }
        }
        .sheet(item: $cleanupSummary) { summary in
            CleanupResultView(
                photoCount: summary.photoCount,
                spaceFreed: summary.spaceFreed,
                failedCount: summary.failedCount,
                bucketLabel: summary.bucketLabel,
                onContinueNextYear: summary.nextBucket.map { nextBucket in
                    {
                        AnalyticsManager.shared.track(
                            .rescanTriggered,
                            properties: ["source": "continue_previous_year", "bucket": nextBucket.displayName]
                        )
                        selectedPhotos.removeAll()
                        scanner.selectBucket(nextBucket)
                    }
                }
            )
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("扫描完成")
                        .font(Design.headlineFont)
                        .foregroundColor(.sageDark)

                    Text("共 \(results.totalPhotoCount) 张照片,耗时 \(String(format: "%.1f", results.scanDuration)) 秒")
                        .font(.caption)
                        .foregroundColor(.warmGray)

                    if results.cloudOnlyPhotoCount > 0 || results.livePhotoCount > 0 {
                        Text(analysisCoverageText)
                            .font(.caption2)
                            .foregroundColor(.warmGray)
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: rescanCurrentBucket) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.sageDark)
                            .frame(width: 36, height: 36)
                            .background(Color.sage.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("重新扫描")

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("可释放")
                            .font(.caption)
                            .foregroundColor(.warmGray)
                        Text(formatBytes(results.totalReclaimableSpace))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.sage)
                    }
                }
            }
            .contentWrapper()
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(scanner.availableYears.sorted(by: >), id: \.self) { year in
                    yearChip(.year(year))
                }
                yearChip(.all)
            }
            .padding(.horizontal, Design.contentHorizontalPadding)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func yearChip(_ bucket: YearBucket) -> some View {
        let isSelected = scanner.selectedBucket == bucket
        return Button(action: {
            selectedPhotos.removeAll()
            catHaptic(.light)
            AnalyticsManager.shared.track(
                .rescanTriggered,
                properties: ["bucket": bucket.displayName]
            )
            scanner.selectBucket(bucket)
        }) {
            Text(bucket.displayName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .sageDark)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 58)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.brandGradient : LinearGradient(colors: [Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 6) {
            ForEach(ResultTab.allCases, id: \.self) { tab in
                Button(action: {
                    catHaptic(.light)
                    selectedTab = tab
                    AnalyticsManager.shared.track(
                        .resultTabSwitched,
                        properties: ["tab": tab.rawValue]
                    )
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(selectedTab == tab ? .white : .sageDark)
                    .background(
                        selectedTab == tab
                        ? Color.brandGradient
                        : LinearGradient(
                            colors: [Color(.systemBackground).opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Capsule())
                }
            }
        }
        .contentWrapper()
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .duplicates:
            DuplicateListView(
                groups: results.duplicateGroups,
                selectedPhotos: $selectedPhotos
            )
        case .similar:
            SimilarListView(
                groups: results.similarGroups,
                selectedPhotos: $selectedPhotos,
                protectedPhotoIDs: protectedDuplicatePhotoIDs
            )
        case .screenshots:
            ScreenshotListView(
                screenshots: results.screenshots,
                recordings: results.screenRecordings,
                selectedPhotos: $selectedPhotos,
                protectedPhotoIDs: protectedDuplicatePhotoIDs
            )
        case .lowQuality:
            LowQualityListView(
                photos: results.lowQualityPhotos,
                selectedPhotos: $selectedPhotos,
                protectedPhotoIDs: protectedDuplicatePhotoIDs
            )
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            Text("已选 \(selectedPhotos.count) 张")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.sageDark)

            Spacer()

            Button(action: {
                catHaptic(.medium)
                AnalyticsManager.shared.track(
                    .deleteConfirmed,
                    properties: ["photo_count": selectedPhotos.count]
                )
                showDeleteConfirm = true
            }) {
                Text("删除 \(selectedPhotos.count) 张")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.appDanger)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.appDanger.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color.appDanger.opacity(0.28), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
        }
        .contentWrapper()
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.sage.opacity(0.1))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Helpers

    private func selectedPhotoItems() -> [PhotoItem] {
        var items: [PhotoItem] = []
        var seenIDs: Set<String> = []

        func appendIfSelected(_ photo: PhotoItem) {
            guard selectedPhotos.contains(photo.id),
                  !protectedDuplicatePhotoIDs.contains(photo.id),
                  !seenIDs.contains(photo.id) else { return }
            seenIDs.insert(photo.id)
            items.append(photo)
        }

        for group in results.duplicateGroups {
            group.photos.forEach(appendIfSelected)
        }
        for group in results.similarGroups {
            group.photos.forEach(appendIfSelected)
        }
        results.screenshots.forEach(appendIfSelected)
        results.screenRecordings.forEach(appendIfSelected)
        results.lowQualityPhotos.forEach(appendIfSelected)
        return items
    }

    private var protectedDuplicatePhotoIDs: Set<String> {
        Set(results.duplicateGroups.compactMap { $0.photos.first?.id })
    }

    private var analysisCoverageText: String {
        var items: [String] = []
        if results.cloudOnlyPhotoCount > 0 {
            items.append("\(results.cloudOnlyPhotoCount) 张仅在 iCloud，未纳入相似分析")
        }
        if results.livePhotoCount > 0 {
            items.append("\(results.livePhotoCount) 张 Live Photo 暂不纳入相似分析")
        }
        return items.joined(separator: " · ")
    }

    private func handleDeleteResult(_ result: DeleteManager.DeleteResult) {
        let failedIDs = Set(result.failedIDs)
        let deletedIDs = Set(selectedPhotos).subtracting(failedIDs)
        let currentBucket = scanner.selectedBucket
        let nextBucket = previousYearBucket(after: currentBucket)

        if !deletedIDs.isEmpty {
            scanner.removeDeletedPhotos(deletedIDs)
        }

        selectedPhotos.removeAll()

        guard result.successCount > 0 else { return }

        AnalyticsManager.shared.track(
            .deleteCompleted,
            properties: [
                "photo_count": result.successCount,
                "failed_count": result.failedCount,
                "space_freed_mb": Int(result.freedSpace / 1_048_576),
                "bucket": currentBucket?.displayName ?? "unknown"
            ]
        )

        let summary = CleanupSummary(
            photoCount: result.successCount,
            spaceFreed: result.freedSpace,
            failedCount: result.failedCount,
            bucketLabel: currentBucket?.displayName,
            nextBucket: nextBucket
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            cleanupSummary = summary
        }
    }

    private func previousYearBucket(after bucket: YearBucket?) -> YearBucket? {
        guard case .year(let year) = bucket,
              let index = scanner.availableYears.firstIndex(of: year) else {
            return nil
        }

        let nextIndex = scanner.availableYears.index(after: index)
        guard scanner.availableYears.indices.contains(nextIndex) else { return nil }
        return .year(scanner.availableYears[nextIndex])
    }

    private func rescanCurrentBucket() {
        guard let bucket = scanner.selectedBucket else { return }
        selectedPhotos.removeAll()
        catHaptic(.medium)
        AnalyticsManager.shared.track(
            .rescanTriggered,
            properties: ["source": "manual_result_header", "bucket": bucket.displayName]
        )
        scanner.selectBucket(bucket, forceRescan: true)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct CleanupSummary: Identifiable {
    let id = UUID()
    let photoCount: Int
    let spaceFreed: Int64
    let failedCount: Int
    let bucketLabel: String?
    let nextBucket: YearBucket?
}
