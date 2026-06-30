import SwiftUI

/// 相似照片列表
/// PRD V1.1 REQ-010: 前 3 组免费预览最佳推荐,第 4 组起需付费解锁
struct SimilarListView: View {
    let groups: [SimilarGroup]
    @Binding var selectedPhotos: Set<String>
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    /// freemium 阈值:前 3 组可看最佳推荐
    private let freeThreshold = 3

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if groups.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.3.group",
                        title: "没有相似照片",
                        subtitle: "这一年保留下来的都挺不一样"
                    )
                } else {
                    Button(action: handleBestSelection) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(appState.isPro ? "保留最佳，选中其余" : "保留最佳，删除其余")
                            Spacer()
                            if appState.isPro {
                                Text("\(totalDeletableCount()) 张")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.secondary)
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
                            showsBestRecommendation: appState.isPro || index < freeThreshold,
                            lockedReason: (!appState.isPro && index >= freeThreshold) ? "升级后显示最佳推荐" : nil
                        ) {
                            showPaywall = true
                        }
                    }

                    if !appState.isPro && groups.count > freeThreshold {
                        Text("前 3 组免费显示最佳推荐，其余组可继续浏览，升级后解锁全量推荐与一键保留最佳。")
                            .font(.caption)
                            .foregroundColor(.warmGray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(appState)
        }
    }

    private func handleBestSelection() {
        if appState.isPro {
            selectAllExceptBest()
        } else {
            showPaywall = true
        }
    }

    private func selectAllExceptBest() {
        for group in groups {
            let sorted = group.photos.sorted { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
            for photo in sorted.dropFirst() {
                selectedPhotos.insert(photo.id)
            }
        }
    }

    private func totalDeletableCount() -> Int {
        groups.reduce(0) { $0 + $1.photos.count - 1 }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

// MARK: - 相似组卡片

struct SimilarGroupCard: View {
    let group: SimilarGroup
    @Binding var selectedPhotos: Set<String>
    let showsBestRecommendation: Bool
    let lockedReason: String?
    let onUnlock: () -> Void
    private let sortedPhotos: [PhotoItem]
    private let bestPhotoID: String?
    private let bestReasonText: String

    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var showsAllPhotos = false

    private let initialPhotoLimit = 60

    init(
        group: SimilarGroup,
        selectedPhotos: Binding<Set<String>>,
        showsBestRecommendation: Bool,
        lockedReason: String?,
        onUnlock: @escaping () -> Void
    ) {
        self.group = group
        self._selectedPhotos = selectedPhotos
        self.showsBestRecommendation = showsBestRecommendation
        self.lockedReason = lockedReason
        self.onUnlock = onUnlock

        let sorted = group.photos.sorted { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
        self.sortedPhotos = sorted
        self.bestPhotoID = sorted.first?.id

        let score = sorted.first?.qualityScore
        if let score, score >= 80 {
            self.bestReasonText = "综合最佳"
        } else if let score, score >= 60 {
            self.bestReasonText = "质量较好"
        } else {
            self.bestReasonText = "推荐保留"
        }
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
                        Text("\(group.photos.count) 张相似照片")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("可释放 \(formatBytes(group.reclaimableSpace))")
                            .font(.caption)
                            .foregroundColor(.warmGray)
                    }

                    Spacer()

                    if let lockedReason {
                        Button(action: onUnlock) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                Text(lockedReason)
                            }
                            .font(.caption2)
                            .foregroundColor(.warmGray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.warmGray.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                            isKeep: showsBestRecommendation && photo.id == bestPhotoID,
                            isBest: showsBestRecommendation && photo.id == bestPhotoID,
                            bestReason: showsBestRecommendation && photo.id == bestPhotoID ? bestReasonText : nil
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
    }

    private var visiblePhotos: [PhotoItem] {
        if showsAllPhotos { return sortedPhotos }
        return Array(sortedPhotos.prefix(initialPhotoLimit))
    }

    private func toggleSelection(_ photo: PhotoItem) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}
