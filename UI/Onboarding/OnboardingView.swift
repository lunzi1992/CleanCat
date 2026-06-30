import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var page = 0

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    page1.tag(0)
                    page2.tag(1)
                    page3.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                VStack(spacing: Design.spaceLG) {
                    HStack(spacing: 8) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(page == i ? Color.sage : Color.sageL)
                                .frame(width: page == i ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.4), value: page)
                        }
                    }

                    Button(action: {
                        catImpact(page == 2 ? .medium : .light)
                        if page < 2 { page += 1 }
                        else { appState.hasCompletedOnboarding = true }
                    }) {
                        Text(page < 2 ? "下一步" : "开始使用轻猫")
                    }
                    .brandButton()
                    .padding(.horizontal, Design.spaceXL)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear { AnalyticsManager.shared.track(.onboardingViewed, properties: ["page": 0]) }
    }

    // MARK: Page 1 — 涂涂的灵感

    var page1: some View {
        VStack(spacing: Design.space2XL) {
            Spacer()
            ZStack {
                Circle().fill(Color.sageL).frame(width: 180, height: 180)
                Circle().fill(Color.brandGradient).frame(width: 120, height: 120)
                Image(systemName: "cat.fill").font(.system(size: 50)).foregroundColor(.white)
            }
            VStack(spacing: Design.spaceSM) {
                Text("涂涂的灵感")
                    .font(Design.titleFont).foregroundColor(Color.sageD)
                Text("每次给它拍照都要连拍几十张\n好看的只有两三张，但一张都不敢删")
                    .font(Design.bodyFont).foregroundColor(Color.grayW)
                    .multilineTextAlignment(.center).lineSpacing(6)
            }
            Spacer()
        }
        .padding(.horizontal, Design.spaceXL)
    }

    // MARK: Page 2 — 100% 本地

    var page2: some View {
        VStack(spacing: Design.space2XL) {
            Spacer()
            ZStack {
                Circle().fill(Color.sageL).frame(width: 180, height: 180)
                Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(Color.brandGradient)
            }
            VStack(spacing: Design.spaceSM) {
                Text("完全本地处理")
                    .font(Design.titleFont).foregroundColor(Color.sageD)
                Text("你的每一张照片都不会离开 iPhone\n不需要注册账号，不上传云端")
                    .font(Design.bodyFont).foregroundColor(Color.grayW)
                    .multilineTextAlignment(.center).lineSpacing(6)
            }
            Spacer()
        }
        .padding(.horizontal, Design.spaceXL)
    }

    // MARK: Page 3 — 按年整理

    var page3: some View {
        VStack(spacing: Design.space2XL) {
            Spacer()
            ZStack {
                Circle().fill(Color.sageL).frame(width: 180, height: 180)
                Image(systemName: "calendar").font(.system(size: 50)).foregroundStyle(Color.brandGradient)
            }
            VStack(spacing: Design.spaceSM) {
                Text("按年整理")
                    .font(Design.titleFont).foregroundColor(Color.sageD)
                Text("选择一年，轻猫帮你找出重复和相似的照片\n慢慢来，不用一次面对所有")
                    .font(Design.bodyFont).foregroundColor(Color.grayW)
                    .multilineTextAlignment(.center).lineSpacing(6)
            }
            Spacer()
        }
        .padding(.horizontal, Design.spaceXL)
    }
}
