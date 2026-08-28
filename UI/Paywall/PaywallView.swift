import SwiftUI

/// 付费墙页面（试用到期 / 用户主动升级入口）
struct PaywallView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: AppState.PurchaseType = .lifetime
    @State private var isPurchasing = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    /// 价格配置
    enum Pricing {
        static let monthly: Double = 18
        static let yearly: Double = 88
        static let lifetime: Double = 118
        /// 限时优惠价（前 1000 名）
        static let lifetimeEarlyBird: Double = 98
    }

    /// 是否使用限时买断优惠
    private var useEarlyBirdLifetime: Bool {
        // TODO: 接入 StoreKit 后用真实销量判定；MVP 阶段恒为 true
        true
    }

    private var lifetimePrice: Double {
        useEarlyBirdLifetime ? Pricing.lifetimeEarlyBird : Pricing.lifetime
    }

    /// 来源（用于埋点）
    var source: String = "settings"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    trialStatusBanner
                    header
                    featureList
                    planPicker
                    purchaseButton
                }
                .padding(.bottom, 32)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color.cream.ignoresSafeArea())
            .onAppear {
                AnalyticsManager.shared.track(.paywallViewed, properties: ["source": source])
            }
            .onDisappear {
                AnalyticsManager.shared.track(.paywallDismissed, properties: ["source": source])
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        AnalyticsManager.shared.track(.purchaseCancelled, properties: ["reason": "user_dismissed", "source": source])
                        dismiss()
                    }
                    .foregroundColor(.warmGray)
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - 试用状态条

    private var trialStatusBanner: some View {
        Group {
            if appState.isTrialActive {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                    Text("试用剩余 \(appState.trialDaysRemaining) 天")
                    Spacer()
                    Text("全部功能已解锁")
                        .font(.caption)
                }
                .font(.subheadline)
                .foregroundColor(.sageDark)
                .padding(12)
                .background(Color.sageLight.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 16)
            } else if appState.isTrialExpired && !appState.isPro {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("试用已到期")
                    Spacer()
                    Text("升级后继续使用")
                        .font(.caption)
                }
                .font(.subheadline)
                .foregroundColor(.appDanger)
                .padding(12)
                .background(Color.appDanger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.sageLight, Color.peachLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "cat.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.brandGradient)
            }

            Text("升级轻猫 Pro")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.sageDark)

            Text("一次购买，永久使用\n或者选择灵活的订阅方案")
                .font(.subheadline)
                .foregroundColor(.warmGray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - 功能列表

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureItem(icon: "sparkles", text: "全量建议保留，智能选出最佳照片")
            FeatureItem(icon: "trash.fill", text: "批量删除，一键清理相似重复")
            FeatureItem(icon: "rectangle.3.group", text: "截图智能分类，敏感证件保护")
            FeatureItem(icon: "video.fill", text: "视频重复检测与低质量识别")
            FeatureItem(icon: "icloud.fill", text: "iCloud 照片按需预览")
            FeatureItem(icon: "hand.raised.fill", text: "100% 本地处理，隐私优先")
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - 方案选择

    private var planPicker: some View {
        VStack(spacing: 12) {
            ForEach([AppState.PurchaseType.yearly, .lifetime, .monthly], id: \.self) { plan in
                PlanCard(
                    plan: plan,
                    price: priceFor(plan),
                    period: periodFor(plan),
                    badge: badgeFor(plan),
                    subtitle: subtitleFor(plan),
                    isSelected: selectedPlan == plan,
                    onTap: {
                        catHaptic(.light)
                        selectedPlan = plan
                        AnalyticsManager.shared.track(
                            .paywallPlanSelected,
                            properties: ["plan": plan.rawValue]
                        )
                    }
                )
            }
        }
        .padding(.horizontal, 20)
    }

    private func priceFor(_ plan: AppState.PurchaseType) -> String {
        switch plan {
        case .monthly: return "¥\(Int(Pricing.monthly))"
        case .yearly: return "¥\(Int(Pricing.yearly))"
        case .lifetime: return "¥\(Int(lifetimePrice))"
        case .none: return ""
        }
    }

    private func periodFor(_ plan: AppState.PurchaseType) -> String {
        switch plan {
        case .monthly: return "/月"
        case .yearly: return "/年"
        case .lifetime: return " 一次买断"
        case .none: return ""
        }
    }

    private func badgeFor(_ plan: AppState.PurchaseType) -> String? {
        switch plan {
        case .lifetime: return useEarlyBirdLifetime ? "限时 ¥98" : "推荐"
        case .yearly: return "省 59%"
        default: return nil
        }
    }

    private func subtitleFor(_ plan: AppState.PurchaseType) -> String? {
        switch plan {
        case .monthly: return "灵活，随时取消"
        case .yearly: return "折合 ¥\(NSDecimalNumber(value: Pricing.yearly / 12).rounding(accordingToBehavior: nil).doubleValue)/月"
        case .lifetime: return "比连续 2 年年度订阅省 ¥\(Int(Pricing.yearly * 2 - lifetimePrice))"
        default: return nil
        }
    }

    // MARK: - 购买按钮

    private var purchaseButton: some View {
        VStack(spacing: 12) {
            Button(action: purchase) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isPurchasing ? "处理中..." : purchaseButtonText)
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.brandGradient)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.sage.opacity(0.3), radius: 10, y: 5)
            }
            .disabled(isPurchasing)

            // 试用期内进入付费墙时，必须提供一个明显的「继续免费使用」出口，
            // 避免用户误解成「试用期还没结束就要付费」。
            if appState.isTrialActive {
                Button(action: {
                    catHaptic(.light)
                    AnalyticsManager.shared.track(
                        .paywallDismissed,
                        properties: ["source": source, "reason": "continue_trial"]
                    )
                    dismiss()
                }) {
                    Text("继续免费使用 \(appState.trialDaysRemaining) 天")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.sageDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .stroke(Color.sage.opacity(0.32), lineWidth: 1)
                        )
                }
            }

            Text("订阅可随时取消，不会自动续费提醒")
                .font(.caption2)
                .foregroundColor(.warmGray)

            Button("恢复购买") {
                restorePurchase()
            }
            .font(.subheadline)
            .foregroundColor(.warmGray)
        }
        .padding(.horizontal, 20)
    }

    private var purchaseButtonText: String {
        switch selectedPlan {
        case .monthly: return "订阅 ¥\(Int(Pricing.monthly))/月"
        case .yearly: return "订阅 ¥\(Int(Pricing.yearly))/年"
        case .lifetime: return "买断 ¥\(Int(lifetimePrice))（永久使用）"
        case .none: return "选择方案"
        }
    }

    private func purchase() {
        catHaptic(.medium)
        AnalyticsManager.shared.track(
            .purchaseInitiated,
            properties: ["plan": selectedPlan.rawValue, "price": priceFor(selectedPlan), "storekit_available": false]
        )

        // MVP 阶段：模拟购买成功
        // TODO: 接入 StoreKit 2 替换
        isPurchasing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isPurchasing = false
            appState.completePurchase(type: selectedPlan)
            AnalyticsManager.shared.track(
                .purchaseCompleted,
                properties: ["plan": selectedPlan.rawValue, "price": priceFor(selectedPlan)]
            )
            alertMessage = "升级成功！全部功能已解锁。"
            showAlert = true
            dismiss()
        }
    }

    private func restorePurchase() {
        AnalyticsManager.shared.track(.restorePurchaseClicked)
        // TODO: 接入 StoreKit 2 恢复
        alertMessage = "内测版暂未接入 App Store 恢复购买。"
        showAlert = true
    }
}

// MARK: - 功能项

private struct FeatureItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.sage)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.sage)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 方案卡片

struct PlanCard: View {
    let plan: AppState.PurchaseType
    let price: String
    let period: String
    let badge: String?
    let subtitle: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(planDisplayName)
                            .font(.headline)
                            .foregroundColor(.sageDark)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(plan == .lifetime ? Color.appDanger : Color.sage)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 2) {
                        Text(price)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.sageDark)
                        Text(period)
                            .font(.subheadline)
                            .foregroundColor(.warmGray)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.warmGray)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .sage : .warmGray)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.sage : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var planDisplayName: String {
        switch plan {
        case .monthly: return "月度订阅"
        case .yearly: return "年度订阅"
        case .lifetime: return "永久买断"
        case .none: return ""
        }
    }
}
