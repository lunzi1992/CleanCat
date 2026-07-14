import SwiftUI

/// 截图/录屏列表
struct ScreenshotListView: View {
    let screenshots: [PhotoItem]
    let recordings: [PhotoItem]
    @Binding var selectedPhotos: Set<String>
    let protectedPhotoIDs: Set<String>
    @State private var previewStartID: String?

    private var totalCount: Int {
        screenshots.count + recordings.count
    }

    private var totalSpace: Int64 {
        screenshots.reduce(0) { $0 + $1.fileSize } +
        recordings.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        Group {
            if screenshots.isEmpty && recordings.isEmpty {
                EmptyStateView(
                    icon: "camera.viewfinder",
                    title: "没有截图",
                    subtitle: "没有找到截图或屏幕录制"
                )
            } else {
                ScrollView {
                LazyVStack(spacing: 16) {
                    SelectAllButton(
                        title: "全选截图与录屏",
                        itemCount: totalCount,
                        spaceToFree: totalSpace
                    ) {
                        selectAll()
                    }

                    if !screenshots.isEmpty {
                        sectionHeader("截图", count: screenshots.count)
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(screenshots) { photo in
                                PhotoThumbnailCell(
                                    photo: photo,
                                    isSelected: selectedPhotos.contains(photo.id),
                                    isKeep: protectedPhotoIDs.contains(photo.id),
                                    showsSelectionControl: !protectedPhotoIDs.contains(photo.id),
                                    onPreview: { previewStartID = photo.id }
                                ) {
                                    toggleSelection(photo)
                                }
                            }
                        }
                    }

                    if !recordings.isEmpty {
                        sectionHeader("屏幕录制", count: recordings.count)
                        ForEach(recordings) { recording in
                            ScreenshotRow(
                                photo: recording,
                                isSelected: selectedPhotos.contains(recording.id),
                                showsSelectionControl: !protectedPhotoIDs.contains(recording.id)
                            ) {
                                toggleSelection(recording)
                            }
                        }
                    }
                }
                .padding(16)
            }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { previewStartID != nil },
                set: { if !$0 { previewStartID = nil } }
            )
        ) {
            if let previewStartID {
                SelectablePhotoPreviewPager(
                    photos: screenshots,
                    initialPhotoID: previewStartID,
                    selectedPhotos: $selectedPhotos,
                    protectedPhotoIDs: protectedPhotoIDs,
                    analyticsSource: "screenshot_preview"
                )
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Text("· \(count) 项")
                .font(.subheadline)
                .foregroundColor(.warmGray)
            Spacer()
        }
    }

    private func selectAll() {
        AnalyticsManager.shared.track(
            .photoSelectAllTapped,
            properties: [
                "source": "screenshots",
                "photo_count": screenshots.count,
                "recording_count": recordings.count
            ]
        )
        for photo in screenshots {
            guard !protectedPhotoIDs.contains(photo.id) else { continue }
            selectedPhotos.insert(photo.id)
        }
        for recording in recordings {
            guard !protectedPhotoIDs.contains(recording.id) else { continue }
            selectedPhotos.insert(recording.id)
        }
    }

    private func toggleSelection(_ photo: PhotoItem) {
        guard !protectedPhotoIDs.contains(photo.id) else { return }
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
            AnalyticsManager.shared.track(
                .photoDeselected,
                properties: ["source": photo.isScreenRecording ? "screen_recording" : "screenshot", "photo_id": photo.id]
            )
        } else {
            selectedPhotos.insert(photo.id)
            AnalyticsManager.shared.track(
                .photoSelected,
                properties: ["source": photo.isScreenRecording ? "screen_recording" : "screenshot", "photo_id": photo.id]
            )
        }
    }
}

// MARK: - 录屏行

struct ScreenshotRow: View {
    let photo: PhotoItem
    let isSelected: Bool
    let showsSelectionControl: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "video.fill")
                .foregroundColor(.sage)
                .frame(width: 48, height: 48)
                .background(Color.sageLight.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("屏幕录制")
                    .font(.subheadline)
                Text(formatBytes(photo.fileSize))
                    .font(.caption)
                    .foregroundColor(.warmGray)
            }

            Spacer()

            if showsSelectionControl {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .appDanger : .warmGray)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundColor(.sage)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard showsSelectionControl else { return }
            onTap()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

// MARK: - 低质量待检查

/// 仅展示严格技术质量候选，用户必须逐张选择，不提供全选操作。
struct LowQualityListView: View {
    let photos: [PhotoItem]
    @Binding var selectedPhotos: Set<String>
    let protectedPhotoIDs: Set<String>
    @State private var previewStartID: String?

    var body: some View {
        Group {
            if photos.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "没有明显低质量照片",
                    subtitle: "轻猫只标记明显模糊或曝光异常的照片"
                )
            } else {
                ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "eye")
                            .foregroundColor(.sage)
                        Text("这些照片仅供你检查，默认不选中，也不会自动删除。")
                            .font(.subheadline)
                            .foregroundColor(.warmGray)
                    }
                    .padding(12)
                    .background(Color.sage.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("(photos.count) 张待检查")
                        .font(.headline)
                        .foregroundColor(.sageDark)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 12) {
                        ForEach(photos) { photo in
                            LowQualityPhotoCell(
                                photo: photo,
                                isSelected: selectedPhotos.contains(photo.id),
                                isProtected: protectedPhotoIDs.contains(photo.id),
                                onPreview: { previewStartID = photo.id }
                            ) {
                                toggleSelection(photo)
                            }
                        }
                    }
                }
                .padding(16)
            }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { previewStartID != nil },
                set: { if !$0 { previewStartID = nil } }
            )
        ) {
            if let previewStartID {
                SelectablePhotoPreviewPager(
                    photos: photos,
                    initialPhotoID: previewStartID,
                    selectedPhotos: $selectedPhotos,
                    protectedPhotoIDs: protectedPhotoIDs,
                    analyticsSource: "low_quality_preview"
                )
            }
        }
    }

    private func toggleSelection(_ photo: PhotoItem) {
        guard !protectedPhotoIDs.contains(photo.id) else { return }

        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
            AnalyticsManager.shared.track(
                .photoDeselected,
                properties: ["source": "low_quality", "photo_id": photo.id]
            )
        } else {
            selectedPhotos.insert(photo.id)
            AnalyticsManager.shared.track(
                .photoSelected,
                properties: ["source": "low_quality", "photo_id": photo.id]
            )
        }
    }
}

private struct LowQualityPhotoCell: View {
    let photo: PhotoItem
    let isSelected: Bool
    let isProtected: Bool
    let onPreview: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhotoThumbnailCell(
                photo: photo,
                isSelected: isSelected,
                isKeep: isProtected,
                showsSelectionControl: !isProtected,
                onPreview: onPreview,
                onTap: onTap
            )

            Text(photo.qualityIssueReason ?? "建议检查")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.warmGray)
                .lineLimit(1)
        }
    }
}
