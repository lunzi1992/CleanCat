import SwiftUI

/// 清理成果展示页（成就正向框架：释放 X GB ≈ 多拍 N 张自拍）
struct CleanupResultView: View {
    let photoCount: Int
    var videoCount: Int = 0
    let spaceFreed: Int64
    var failedCount: Int = 0
    var bucketLabel: String? = nil
    var onContinueNextYear: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var confettiScale: CGFloat = 0.5

    private var mediaSummary: MediaCountSummary {
        MediaCountSummary(photoCount: photoCount, videoCount: videoCount)
    }

    /// 估算"多拍多少张自拍"（按每张自拍约 5MB 估算）
    private var selfieEquivalent: Int {
        let bytesPerSelfie: Int64 = 5 * 1024 * 1024
        return Int(spaceFreed / bytesPerSelfie)
    }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // 成功图标 + 庆祝动画
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.sageLight, Color.peachLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(confettiScale)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.brandGradient)
                        .scaleEffect(confettiScale)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        confettiScale = 1.0
                    }
                }

                VStack(spacing: 16) {
                    Text(bucketLabel.map { "你的\($0)整理完毕" } ?? "整理完成！")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.sageDark)

                    if selfieEquivalent > 0 {
                        VStack(spacing: 6) {
                            Text("释放了 \(formatBytes(spaceFreed))")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.warmGray)

                            Text("≈ 多拍 \(selfieEquivalent) 张自拍 📸")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.sage)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }

                    HStack(spacing: 20) {
                        StatCard(
                            icon: "photo.on.rectangle.angled",
                            value: "\(mediaSummary.totalCount)",
                            label: "已清理"
                        )

                        if failedCount > 0 {
                            StatCard(
                                icon: "exclamationmark.triangle",
                                value: "\(failedCount)",
                                label: "失败",
                                color: .appDanger
                            )
                        }
                    }

                    Text("\(mediaSummary.countText)已移至「最近删除」\n30 天内可恢复")
                        .font(.caption)
                        .foregroundColor(.warmGray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                Spacer()

                VStack(spacing: 16) {
                    Button(action: {
                        catHaptic(.medium)
                        dismiss()
                    }) {
                        Text("完成")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.brandGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: Color.sage.opacity(0.3), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)

                    if let onContinue = onContinueNextYear {
                        Button(action: {
                            catHaptic(.light)
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onContinue()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.right")
                                Text("继续整理上一年")
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.sageDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.sage.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        catHaptic(.light)
                        AnalyticsManager.shared.track(
                            .shareClicked,
                            properties: [
                                "photo_count": photoCount,
                                "video_count": videoCount,
                                "space_freed_mb": Int(spaceFreed / 1_048_576)
                            ]
                        )
                        showShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享成果")
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.warmGray)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
                .contentWrapper()
                .padding(.bottom, 48)
            }
            .frame(maxWidth: 480) // 大屏居中
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    private var shareText: String {
        if selfieEquivalent > 0 {
            return "用轻猫清理了 \(mediaSummary.countText)，释放 \(formatBytes(spaceFreed))，≈ 多拍 \(selfieEquivalent) 张自拍 🐱✨"
        }
        return "用轻猫清理了 \(mediaSummary.countText)，释放 \(formatBytes(spaceFreed)) 🐱✨"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter().string(fromByteCount: bytes)
    }
}

// MARK: - 分享 Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 统计卡片

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .sage

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.sageDark)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.warmGray)
        }
        .frame(width: 110)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
