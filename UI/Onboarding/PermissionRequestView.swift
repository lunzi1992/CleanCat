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

                VStack(spacing: Design.spaceSM) {
                    HStack(spacing: Design.spaceSM) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color.sage).font(.caption)
                        Text("不联网").font(Design.captionFont).foregroundColor(Color.grayW)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color.sage).font(.caption)
                        Text("不上传").font(Design.captionFont).foregroundColor(Color.grayW)
                    }
                    HStack(spacing: Design.spaceSM) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color.sage).font(.caption)
                        Text("不注册").font(Design.captionFont).foregroundColor(Color.grayW)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color.sage).font(.caption)
                        Text("100% 本地").font(Design.captionFont).foregroundColor(Color.grayW)
                    }
                }
                .glassCard()
                .padding(.horizontal, Design.spaceXL)

                Spacer()

                Button(action: requestPermission) {
                    Text(requesting ? "请稍候..." : "授权访问相册")
                }
                .brandButton(disabled: requesting)
                .disabled(requesting)
                .padding(.horizontal, Design.spaceXL)
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
