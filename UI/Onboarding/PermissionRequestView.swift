import SwiftUI
import Photos

struct PermissionRequestView: View {
    @EnvironmentObject var appState: AppState
    @State private var requesting = false

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: Design.space2XL) {
                Spacer()

                ZStack {
                    Circle().fill(Color.sageL).frame(width: 160, height: 160)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52)).foregroundStyle(Color.brandGradient)
                }

                VStack(spacing: Design.spaceSM) {
                    Text("访问相册")
                        .font(Design.titleFont).foregroundColor(Color.sageD)
                    Text("轻猫需要查看照片才能帮你整理\n所有分析都在本机完成，绝不联网")
                        .font(Design.bodyFont).foregroundColor(Color.grayW)
                        .multilineTextAlignment(.center).lineSpacing(6)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Design.spaceSM),
                        GridItem(.flexible(), spacing: Design.spaceSM)
                    ],
                    spacing: Design.spaceSM
                ) {
                    PrivacyPromiseItem(icon: "wifi.slash", title: "不联网")
                    PrivacyPromiseItem(icon: "icloud.slash", title: "不上传")
                    PrivacyPromiseItem(icon: "person.crop.circle.badge.xmark", title: "不注册")
                    PrivacyPromiseItem(icon: "iphone.gen3", title: "本机分析")
                }
                .glassCard()
                .contentWrapper()

                Spacer()

                Button(action: requestPermission) {
                    Text(requesting ? "请稍候..." : "授权访问相册")
                }
                .brandButton(disabled: requesting)
                .disabled(requesting)
                .contentWrapper()
                .padding(.bottom, 50)
            }
        }
        .onAppear { AnalyticsManager.shared.track(.permissionRequested) }
    }

    private func requestPermission() {
        requesting = true
        catImpact(.medium)
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                requesting = false
                appState.authorizationStatus = status
                switch status {
                case .authorized, .limited:
                    AnalyticsManager.shared.track(.permissionGranted, properties: ["status": status.rawValue])
                case .denied, .restricted:
                    AnalyticsManager.shared.track(.permissionDenied, properties: ["status": status.rawValue])
                default:
                    break
                }
            }
        }
    }
}

private struct PrivacyPromiseItem: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.brandGradient)
                .frame(width: 42, height: 42)
                .background(Color.sageL.opacity(0.75), in: Circle())

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Color.sageD)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: Design.radiusXS))
    }
}
