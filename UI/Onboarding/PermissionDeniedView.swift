import SwiftUI
import Photos

struct PermissionDeniedView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: Design.space2XL) {
                Spacer()

                ZStack {
                    Circle().fill(Color.peachL).frame(width: 140, height: 140)
                    Image(systemName: "cat.fill").font(.system(size: 40)).foregroundStyle(Color.grayW)
                }

                VStack(spacing: Design.spaceSM) {
                    Text("没有权限，涂涂帮不了你")
                        .font(Design.headlineFont).foregroundColor(Color.sageD)
                    Text("需要相册访问权限才能扫描照片\n请在设置中允许访问")
                        .font(Design.bodyFont).foregroundColor(Color.grayW)
                        .multilineTextAlignment(.center).lineSpacing(6)
                }

                Button(action: openSettings) {
                    Label("去设置", systemImage: "gear")
                }
                .brandButton()
                .padding(.horizontal, Design.spaceXL)

                Spacer()
            }
        }
    }

    private func openSettings() {
        catImpact(.light)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
