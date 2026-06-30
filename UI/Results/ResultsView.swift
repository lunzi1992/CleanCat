import SwiftUI

/// 扫描结果展示页(三 Tab,奶油白配色)
struct ResultsView: View {
    let results: ScanResults
    @ObservedObject var scanner: PhotoScanner
    @State private var selectedTab: ResultTab = .duplicates
    @State private var showDeleteConfirm = false
    @State private var selectedPhotos: Set<String> = []

    enum ResultTab: String, CaseIterable {
        case duplicates = "重复照片"
        case similar = "相似照片"
        case screenshots = "截图"

        var icon: String {
            switch self {
            case .duplicates: return "doc.on.doc"
            case .similar: return "rectangle.3.group"
            case .screenshots: return "camera.viewfinder"
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
                    "screenshots": results.screenshots.count
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
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("扫描完成")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.sageDark)

                    Text("共 \(results.totalPhotoCount) 张照片,耗时 \(String(format: "%.1f", results.scanDuration)) 秒")
                        .font(.caption)
                        .foregroundColor(.warmGray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("可释放")
                        .font(.caption)
                        .foregroundColor(.warmGray)
                    Text(formatBytes(results.totalReclaimableSpace))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.sage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(scanner.availableYears, id: \.self) { year in
                    yearChip(.year(year))
                }
                yearChip(.all)
            }
            .padding(.horizontal, 20)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.brandGradient : LinearGradient(colors: [Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(ResultTab.allCases, id: \.self) { tab in
                Button(action: {
                    catHaptic(.light)
                    selectedTab = tab
                    AnalyticsManager.shared.track(
                        .resultTabSwitched,
                        properties: ["tab": tab.rawValue]
                    )
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.subheadline)
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }

                        Rectangle()
                            .fill(selectedTab == tab ? Color.sage : Color.clear)
                            .frame(height: 2)
                    }
                }
                .foregroundColor(selectedTab == tab ? .sageDark : .warmGray)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
                selectedPhotos: $selectedPhotos
            )
        case .screenshots:
            ScreenshotListView(
                screenshots: results.screenshots,
                recordings: results.screenRecordings,
                selectedPhotos: $selectedPhotos
            )
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            Text("已选 \(selectedPhotos.count) 张")
                .font(.subheadline)
                .foregroundColor(.warmGray)

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
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.appDanger)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
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
            guard selectedPhotos.contains(photo.id), !seenIDs.contains(photo.id) else { return }
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
        return items
    }

    private func handleDeleteResult(_ result: DeleteManager.DeleteResult) {
        let failedIDs = Set(result.failedIDs)
        let deletedIDs = Set(selectedPhotos).subtracting(failedIDs)

        if !deletedIDs.isEmpty {
            scanner.removeDeletedPhotos(deletedIDs)
        }

        selectedPhotos.removeAll()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
