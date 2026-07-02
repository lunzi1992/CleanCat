import SwiftUI

/// 截图/录屏列表
struct ScreenshotListView: View {
    let screenshots: [PhotoItem]
    let recordings: [PhotoItem]
    @Binding var selectedPhotos: Set<String>

    private var totalCount: Int {
        screenshots.count + recordings.count
    }

    private var totalSpace: Int64 {
        screenshots.reduce(0) { $0 + $1.fileSize } +
        recordings.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
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
                                    isKeep: false
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
                                isSelected: selectedPhotos.contains(recording.id)
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
            selectedPhotos.insert(photo.id)
        }
        for recording in recordings {
            selectedPhotos.insert(recording.id)
        }
    }

    private func toggleSelection(_ photo: PhotoItem) {
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

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(isSelected ? .appDanger : .warmGray)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onTap() }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}
