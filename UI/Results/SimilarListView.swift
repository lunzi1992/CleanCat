import SwiftUI

/// 相似照片列表
/// 试用/付费机制：7天试用全功能，到期后保留建议需付费
struct SimilarListView: View {
    let groups: [SimilarGroup]
    @Binding var selectedPhotos: Set<String>
    let protectedPhotoIDs: Set<String>
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if groups.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.3.group",
                        title: "没有可能相似的照片",
                        subtitle: "这一年保留下来的都挺不一样"
                    )
                } else {
                    Button(action: handleBestSelection) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("保留建议，选中其余")
                            Spacer()
                            if appState.hasFullAccess {
                                Text("\(totalDeletableCount()) 张")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.appDanger)
                            }
                        }
                        .font(.subheadline)
                        .padding(12)
                        .background(Color.sage.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        SimilarGroupCard(
                            group: group,
                            selectedPhotos: $selectedPhotos,
                            protectedPhotoIDs: protectedPhotoIDs,
                            showsBestRecommendation: appState.hasFullAccess,
                            lockedReason: nil
                        )
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "similar_best_selection")
                .environmentObject(appState)
        }
    }

    private func handleBestSelection() {
        if appState.hasFullAccess {
            selectAllExceptBest()
        } else {
            catHaptic(.light)
            AnalyticsManager.shared.track(
                .bestPhotoPreviewExhausted,
                properties: ["reason": "feature_locked", "group_count": groups.count]
            )
            showPaywall = true
        }
    }

    private func selectAllExceptBest() {
        AnalyticsManager.shared.track(
            .photoSelectAllTapped,
            properties: ["source": "similar", "group_count": highConfidenceGroups.count]
        )
        for group in highConfidenceGroups {
            let sorted = group.photos.sorted(by: PhotoItem.isPreferredForRecommendation)
            for photo in sorted.dropFirst() {
                guard !protectedPhotoIDs.contains(photo.id) else { continue }
                selectedPhotos.insert(photo.id)
            }
        }
    }

    private func totalDeletableCount() -> Int {
        highConfidenceGroups.reduce(0) { $0 + $1.photos.count - 1 }
    }

    private var highConfidenceGroups: [SimilarGroup] {
        groups.filter { $0.confidence == .high }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

// MARK: - 相似组卡片

struct SimilarGroupCard: View {
    let group: SimilarGroup
    @Binding var selectedPhotos: Set<String>
    let protectedPhotoIDs: Set<String>
    let showsBestRecommendation: Bool
    let lockedReason: String?
    private let sortedPhotos: [PhotoItem]
    private let bestPhotoID: String?
    private let bestReasonText: String

    @State private var isExpanded = false
    @State private var showsAllPhotos = false
    @State private var previewStartID: String?

    private let initialPhotoLimit = 60

    init(
        group: SimilarGroup,
        selectedPhotos: Binding<Set<String>>,
        protectedPhotoIDs: Set<String>,
        showsBestRecommendation: Bool,
        lockedReason: String?
    ) {
        self.group = group
        self._selectedPhotos = selectedPhotos
        self.protectedPhotoIDs = protectedPhotoIDs
        self.showsBestRecommendation = showsBestRecommendation
        self.lockedReason = lockedReason

        let sorted = group.photos.sorted(by: PhotoItem.isPreferredForRecommendation)
        self.sortedPhotos = sorted
        self.bestPhotoID = sorted.first?.id

        self.bestReasonText = sorted.first?.qualityReason ?? "建议保留"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 组头
            Button(action: {
                isExpanded.toggle()
                if !isExpanded {
                    showsAllPhotos = false
                }
            }) {
                HStack {
                    Image(systemName: "rectangle.3.group.fill")
                        .foregroundColor(.sage)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(group.photos.count) 张可能相似")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ConfidenceBadge(confidence: group.confidence)
                        }
                        Text(group.confidence == .high ? "可释放 \(formatBytes(group.reclaimableSpace))" : "建议逐张检查")
                            .font(.caption)
                            .foregroundColor(.warmGray)

                        ReasonTagRow(tags: group.reasonTags)
                    }

                    Spacer()

                    if let lockedReason {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.tap")
                            Text(lockedReason)
                        }
                        .font(.caption2)
                        .foregroundColor(.warmGray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.warmGray.opacity(0.1))
                        .clipShape(Capsule())
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.warmGray)
                    }
                }
                .padding(12)
            }

            if isExpanded {
                Divider().padding(.horizontal, 12)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(visiblePhotos) { photo in
                        PhotoThumbnailCell(
                            photo: photo,
                            isSelected: selectedPhotos.contains(photo.id),
                            isKeep: protectedPhotoIDs.contains(photo.id) || (showsBestRecommendation && photo.id == bestPhotoID),
                            isBest: showsBestRecommendation && photo.id == bestPhotoID,
                            bestReason: showsBestRecommendation && photo.id == bestPhotoID ? bestReasonText : nil,
                            showsSelectionControl: !protectedPhotoIDs.contains(photo.id),
                            onPreview: { previewStartID = photo.id }
                        ) {
                            toggleSelection(photo)
                        }
                    }
                }
                .padding(12)

                if sortedPhotos.count > initialPhotoLimit && !showsAllPhotos {
                    Button(action: { showsAllPhotos = true }) {
                        Text("继续显示剩余 \(sortedPhotos.count - initialPhotoLimit) 张")
                            .font(.subheadline)
                            .foregroundColor(.sageDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fullScreenCover(
            isPresented: Binding(
                get: { previewStartID != nil },
                set: { if !$0 { previewStartID = nil } }
            )
        ) {
            if let previewStartID {
                SelectablePhotoPreviewPager(
                    photos: sortedPhotos,
                    initialPhotoID: previewStartID,
                    selectedPhotos: $selectedPhotos,
                    protectedPhotoIDs: protectedPhotoIDs,
                    analyticsSource: "similar_preview"
                )
            }
        }
    }

    private var visiblePhotos: [PhotoItem] {
        if showsAllPhotos { return sortedPhotos }
        return Array(sortedPhotos.prefix(initialPhotoLimit))
    }

    private func toggleSelection(_ photo: PhotoItem) {
        guard !protectedPhotoIDs.contains(photo.id) else { return }
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
            AnalyticsManager.shared.track(
                .photoDeselected,
                properties: ["source": "similar"]
            )
        } else {
            selectedPhotos.insert(photo.id)
            AnalyticsManager.shared.track(
                .photoSelected,
                properties: ["source": "similar"]
            )
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}
