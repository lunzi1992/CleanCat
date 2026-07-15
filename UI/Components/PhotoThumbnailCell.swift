import SwiftUI
import Photos
import AVKit

/// 照片缩略图单元格
struct PhotoThumbnailCell: View {
    let photo: PhotoItem
    let isSelected: Bool
    var isKeep: Bool = false
    var isBest: Bool = false
    var bestReason: String? = nil
    var showsSelectionControl: Bool = true
    var onPreview: (() -> Void)? = nil
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var showPreview = false

    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 110)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 110)
                    .overlay(
                        ProgressView()
                            .tint(.secondary)
                    )
            }

            VStack {
                HStack {
                    if isKeep {
                        Text("保留")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.sage)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if showsSelectionControl {
                        Button(action: onTap) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(isSelected ? .appDanger : .white)
                                .shadow(radius: 1)
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSelected ? "取消选择" : "选择照片")
                    }
                }
                .padding(6)

                Spacer()

                if isBest, let reason = bestReason {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                        Text(reason)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sage.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(6)
                }

                if photo.isVideo || !isKeep {
                    HStack {
                        if photo.isVideo, let duration = photo.videoDuration {
                            HStack(spacing: 2) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 8))
                                Text(formatDuration(duration))
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        if !isKeep {
                            Text(formatBytes(photo.fileSize))
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.appDanger : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if let onPreview {
                onPreview()
            } else {
                showPreview = true
            }
        }
        .onAppear { loadThumbnail() }
        .onDisappear { cancelThumbnailRequest() }
        .fullScreenCover(isPresented: $showPreview) {
            PhotoPreviewView(photo: photo)
        }
    }

    private func loadThumbnail() {
        guard thumbnail == nil, requestID == nil else { return }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 180 * scale, height: 180 * scale)
        requestID = manager.requestImage(
            for: photo.asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                return
            }
            if let image {
                DispatchQueue.main.async {
                    self.thumbnail = image
                    self.requestID = nil
                }
            }
        }
    }

    private func cancelThumbnailRequest() {
        guard let requestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        self.requestID = nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// 可选择照片的连续预览：左右对比后可直接选择或取消选择当前照片。
struct SelectablePhotoPreviewPager: View {
    let photos: [PhotoItem]
    let initialPhotoID: String
    @Binding var selectedPhotos: Set<String>
    let protectedPhotoIDs: Set<String>
    let analyticsSource: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentPhotoID: String

    init(
        photos: [PhotoItem],
        initialPhotoID: String,
        selectedPhotos: Binding<Set<String>>,
        protectedPhotoIDs: Set<String>,
        analyticsSource: String = "photo_preview"
    ) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self._selectedPhotos = selectedPhotos
        self.protectedPhotoIDs = protectedPhotoIDs
        self.analyticsSource = analyticsSource
        self._currentPhotoID = State(initialValue: initialPhotoID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentPhotoID) {
                ForEach(photos) { photo in
                    SelectablePhotoPreviewPage(photo: photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack {
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("关闭预览")

                    Spacer()

                    Text("\(currentIndex + 1) / \(photos.count)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.45), in: Capsule())

                    if isCurrentPhotoProtected {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.sageLight)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.45), in: Circle())
                            .accessibilityLabel("此照片已保留")
                    } else {
                        Button(action: toggleCurrentSelection) {
                            Image(systemName: isCurrentPhotoSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundColor(isCurrentPhotoSelected ? .appDanger : .white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.45), in: Circle())
                        }
                        .accessibilityLabel(isCurrentPhotoSelected ? "取消选择当前照片" : "选择当前照片")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()
            }
        }
    }

    private var currentIndex: Int {
        photos.firstIndex(where: { $0.id == currentPhotoID }) ?? 0
    }

    private var isCurrentPhotoSelected: Bool {
        selectedPhotos.contains(currentPhotoID)
    }

    private var isCurrentPhotoProtected: Bool {
        protectedPhotoIDs.contains(currentPhotoID)
    }

    private func toggleCurrentSelection() {
        guard !isCurrentPhotoProtected else { return }

        if selectedPhotos.contains(currentPhotoID) {
            selectedPhotos.remove(currentPhotoID)
            AnalyticsManager.shared.track(
                .photoDeselected,
                properties: ["source": analyticsSource, "photo_id": currentPhotoID]
            )
        } else {
            selectedPhotos.insert(currentPhotoID)
            AnalyticsManager.shared.track(
                .photoSelected,
                properties: ["source": analyticsSource, "photo_id": currentPhotoID]
            )
        }
    }
}

private struct SelectablePhotoPreviewPage: View {
    let photo: PhotoItem

    var body: some View {
        CloudMediaPreviewContent(photo: photo)
    }
}

struct PhotoPreviewView: View {
    let photo: PhotoItem

    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CloudMediaPreviewContent(photo: photo)

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("关闭预览")

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()
            }
        }
    }
}

private struct CloudMediaPreviewContent: View {
    let photo: PhotoItem

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var progress: Double = 0
    @State private var loadError: String?

    var body: some View {
        Group {
            if photo.isVideo, let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else if let loadError {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.system(size: 36))
                    Text(loadError)
                        .font(.headline)
                    Button("重新加载", action: retry)
                        .buttonStyle(.borderedProminent)
                }
                .foregroundColor(.white.opacity(0.9))
            } else {
                VStack(spacing: 12) {
                    if progress > 0 {
                        ProgressView(value: progress)
                            .frame(width: 180)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                    } else {
                        ProgressView()
                    }
                    Text(photo.isVideo ? "正在从 iCloud 加载视频..." : "正在从 iCloud 加载照片...")
                        .font(.caption)
                }
                .tint(.white)
                .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadMedia() }
        .onDisappear { cancelRequest() }
    }

    private func loadMedia() {
        guard image == nil, player == nil, requestID == nil else { return }
        loadError = nil
        progress = 0

        if photo.isVideo {
            loadVideo()
        } else {
            loadPhoto()
        }
    }

    private func loadPhoto() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        options.progressHandler = { value, error, _, _ in
            DispatchQueue.main.async {
                progress = value
                if let error { loadError = error.localizedDescription }
            }
        }

        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: screen.width * scale, height: screen.height * scale)

        requestID = PHImageManager.default().requestImage(
            for: photo.asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            DispatchQueue.main.async {
                if let result { image = result }
                if !degraded {
                    requestID = nil
                    if result == nil, loadError == nil {
                        loadError = "无法加载这张照片，请检查网络后重试"
                    }
                }
            }
        }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.progressHandler = { value, error, _, _ in
            DispatchQueue.main.async {
                progress = value
                if let error { loadError = error.localizedDescription }
            }
        }

        requestID = PHImageManager.default().requestPlayerItem(
            forVideo: photo.asset,
            options: options
        ) { item, info in
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled { return }
            DispatchQueue.main.async {
                requestID = nil
                if let item {
                    player = AVPlayer(playerItem: item)
                    player?.play()
                } else if loadError == nil {
                    loadError = "无法加载这个视频，请检查网络后重试"
                }
            }
        }
    }

    private func retry() {
        cancelRequest()
        image = nil
        player = nil
        loadMedia()
    }

    private func cancelRequest() {
        player?.pause()
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
            self.requestID = nil
        }
    }
}
