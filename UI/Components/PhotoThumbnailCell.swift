import SwiftUI
import Photos

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

                if !isKeep {
                    HStack {
                        Spacer()
                        Text(formatBytes(photo.fileSize))
                            .font(.system(size: 9))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
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

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else if didFinishLoading {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 36))
                    Text("这张照片可能仅保存在 iCloud 中")
                        .font(.headline)
                    Text("当前不会自动下载云端原图")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadPreviewImage() }
        .onDisappear { cancelPreviewRequest() }
    }

    private func loadPreviewImage() {
        guard image == nil, requestID == nil else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: screen.width * scale, height: screen.height * scale)

        requestID = PHImageManager.default().requestImage(
            for: photo.asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                return
            }
            DispatchQueue.main.async {
                self.image = image
                self.didFinishLoading = true
                self.requestID = nil
            }
        }
    }

    private func cancelPreviewRequest() {
        guard let requestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        self.requestID = nil
    }
}

struct PhotoPreviewView: View {
    let photo: PhotoItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var didFinishLoading = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else if didFinishLoading {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 36))
                    Text("这张照片可能仅保存在 iCloud 中")
                        .font(.headline)
                    Text("当前不会自动下载云端原图")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding()
            } else {
                ProgressView()
                    .tint(.white)
            }

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
        .onAppear { loadPreviewImage() }
        .onDisappear { cancelPreviewRequest() }
    }

    private func loadPreviewImage() {
        guard image == nil, requestID == nil else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false

        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: screen.width * scale, height: screen.height * scale)

        requestID = PHImageManager.default().requestImage(
            for: photo.asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                return
            }
            DispatchQueue.main.async {
                self.image = image
                self.didFinishLoading = true
                self.requestID = nil
            }
        }
    }

    private func cancelPreviewRequest() {
        guard let requestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        self.requestID = nil
    }
}
