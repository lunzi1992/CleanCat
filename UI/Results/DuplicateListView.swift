import SwiftUI

/// 重复照片列表
struct DuplicateListView: View {
    let groups: [DuplicateGroup]
    @Binding var selectedPhotos: Set<String>

    private var totalDeletableCount: Int {
        groups.reduce(0) { $0 + $1.photos.count - 1 }
    }

    private var totalReclaimable: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableSpace }
    }

    var body: some View {
        if groups.isEmpty {
            EmptyStateView(
                icon: "doc.on.doc",
                title: "没有重复照片",
                subtitle: "你的相册很整洁!"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    SelectAllButton(
                        title: "全选重复照片",
                        itemCount: totalDeletableCount,
                        spaceToFree: totalReclaimable
                    ) {
                        selectAll()
                    }

                    ForEach(groups) { group in
                        DuplicateGroupCard(
                            group: group,
                            selectedPhotos: $selectedPhotos
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private func selectAll() {
        AnalyticsManager.shared.track(
            .photoSelectAllTapped,
            properties: ["source": "duplicates", "group_count": groups.count]
        )
        for group in groups {
            for photo in group.photos.dropFirst() {
                selectedPhotos.insert(photo.id)
            }
        }
    }
}

// MARK: - 重复照片组卡片

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @Binding var selectedPhotos: Set<String>
    @State private var isExpanded = false
    @State private var showsAllPhotos = false
    @State private var previewStartID: String?

    private let initialPhotoLimit = 60

    private var deletablePhotos: [PhotoItem] {
        Array(group.photos.dropFirst())
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                isExpanded.toggle()
                if !isExpanded {
                    showsAllPhotos = false
                }
            }) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundColor(.peach)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(group.photos.count) \(duplicateNoun(for: group))")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ConfidenceBadge(confidence: group.confidence)
                        }
                        Text("可释放 \(formatBytes(group.reclaimableSpace))")
                            .font(.caption)
                            .foregroundColor(.sage)

                        ReasonTagRow(tags: group.reasonTags)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.warmGray)
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
                            isKeep: photo.id == group.photos.first?.id,
                            showsSelectionControl: photo.id != group.photos.first?.id,
                            onPreview: { previewStartID = photo.id }
                        ) {
                            toggleSelection(photo)
                        }
                    }
                }
                .padding(12)

                if group.photos.count > initialPhotoLimit && !showsAllPhotos {
                    Button(action: { showsAllPhotos = true }) {
                        Text("继续显示剩余 \(group.photos.count - initialPhotoLimit) 张")
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
                    photos: group.photos,
                    initialPhotoID: previewStartID,
                    selectedPhotos: $selectedPhotos,
                    protectedPhotoIDs: Set(group.photos.prefix(1).map(\.id)),
                    analyticsSource: "duplicate_preview"
                )
            }
        }
    }

    private var visiblePhotos: [PhotoItem] {
        if showsAllPhotos { return group.photos }
        return Array(group.photos.prefix(initialPhotoLimit))
    }

    /// 根据组内资源类型返回合适的名词："张完全相同的照片" / "个完全相同的视频" / "个完全相同的照片/视频"
    private func duplicateNoun(for group: DuplicateGroup) -> String {
        let hasVideo = group.photos.contains { $0.isVideo }
        let hasLivePhoto = group.photos.contains { $0.isLivePhoto }
        let hasPhoto = group.photos.contains { !$0.isVideo && !$0.isLivePhoto }

        if hasVideo && !hasPhoto && !hasLivePhoto {
            return "个完全相同的视频"
        } else if hasVideo {
            // 混合类型（理论上有 hash 前缀隔离不应出现，兜底）
            return "个完全相同的照片/视频"
        } else {
            return "张完全相同的照片"
        }
    }

    private func toggleSelection(_ photo: PhotoItem) {
        guard photo.id != group.photos.first?.id else { return }
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
            AnalyticsManager.shared.track(
                .photoDeselected,
                properties: ["source": "duplicates", "photo_id": photo.id]
            )
        } else {
            selectedPhotos.insert(photo.id)
            AnalyticsManager.shared.track(
                .photoSelected,
                properties: ["source": "duplicates", "photo_id": photo.id]
            )
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}
