import SwiftUI

/// 删除确认弹窗（仪式感设计：告别微互动 + 成就正向框架）
struct DeleteConfirmView: View {
    let photos: [PhotoItem]
    let onConfirm: (DeleteManager.DeleteResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var showFarewell = false
    @State private var deleteError: String?
    @State private var fadeOpacity: Double = 1.0

    private let deleteManager = DeleteManager()

    private var mediaSummary: MediaCountSummary { MediaCountSummary(items: photos) }
    private var spaceToFree: Int64 {
        photos.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cream.ignoresSafeArea()

                if showFarewell {
                    farewellView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    confirmView
                }
            }
            .navigationBarHidden(true)
            .frame(maxWidth: 480) // 大屏居中显示
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("删除失败", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("确定", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(deleteError ?? "未知错误")
            }
        }
    }

    // MARK: - 确认界面

    private var confirmView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.appDanger.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "trash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.appDanger)
            }

            VStack(spacing: 12) {
                Text("确认删除？")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.sageDark)

                VStack(spacing: 6) {
                    Text("将删除 \(mediaSummary.countText)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("释放约 \(formatBytes(spaceToFree)) 空间")
                        .font(.subheadline)
                        .foregroundColor(.sage)
                }

                Text("所选项目将移至「最近删除」相簿\n30 天内可从系统「照片」App 中恢复")
                    .font(.caption)
                    .foregroundColor(.warmGray)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    catHaptic(.medium)
                    startFarewell()
                }) {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isDeleting ? "正在删除..." : "确认删除")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.appDanger)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color.appDanger.opacity(0.3), radius: 10, y: 5)
                }
                .disabled(isDeleting)

                Button("取消") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.warmGray)
                .disabled(isDeleting)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - 告别微互动（逐张淡出动画）

    private var farewellView: some View {
        VStack(spacing: 32) {
            Spacer()

            // 逐张淡出的照片图标
            ZStack {
                ForEach(0..<min(mediaSummary.totalCount, 8), id: \.self) { i in
                    FarewellPhotoIcon(
                        index: i,
                        total: min(mediaSummary.totalCount, 8),
                        startDelay: Double(i) * 0.08
                    )
                }
            }
            .frame(height: 180)
            .opacity(fadeOpacity)

            VStack(spacing: 12) {
                Text("正在整理 \(mediaSummary.countText)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.sageDark)
                    .multilineTextAlignment(.center)

                Text("陪伴你的时光")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.warmGray)
                    .padding(.top, -4)

                HStack(spacing: 6) {
                    Image(systemName: "cat.fill")
                        .font(.caption)
                    Text("轻猫正在帮你整理...")
                        .font(.caption)
                }
                .foregroundColor(.warmGray.opacity(0.8))
                .padding(.top, 12)
            }
            .opacity(fadeOpacity)

            Spacer()
        }
    }

    // MARK: - 动作

    private func startFarewell() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showFarewell = true
        }
        // 1.5 秒后开始淡出
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.7)) {
                fadeOpacity = 0.0
            }
        }
        // 1.5 秒后执行删除
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            performDelete()
        }
    }

    private func performDelete() {
        isDeleting = true
        Task {
            let result = await deleteManager.deletePhotos(photos)
            await MainActor.run {
                isDeleting = false

                if result.successCount == 0 && result.failedCount > 0 {
                    deleteError = result.errors.first?.localizedDescription ?? "删除失败，请重试"
                    withAnimation { showFarewell = false; fadeOpacity = 1.0 }
                } else {
                    onConfirm(result)
                    dismiss()
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

// MARK: - 单张告别照片图标

private struct FarewellPhotoIcon: View {
    let index: Int
    let total: Int
    let startDelay: Double

    @State private var opacity: Double = 1.0
    @State private var yOffset: CGFloat = 0

    var body: some View {
        Image(systemName: "photo.fill")
            .font(.system(size: 36))
            .foregroundColor(Color.sage.opacity(0.5))
            .offset(
                x: CGFloat(index - total / 2) * 22,
                y: yOffset
            )
            .rotationEffect(.degrees(Double(index - total / 2) * 4))
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        opacity = 0
                        yOffset = -20
                    }
                }
            }
    }
}
