import SwiftUI

/// 付费墙页面
struct PaywallView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PlanType = .yearly
    @State private var isPurchasing = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    enum PlanType: String, CaseIterable {
        case monthly = "月度"
        case yearly = "年度"
        case lifetime = "永久"
    }

    /// 价格配置(根据发布时间动态判断早鸟价)
    struct Pricing {
        let monthly: Double = 9
        let yearly: Double = 58
        let lifetime: Double = 68   // 早鸟价,3个月后切换为 98
        let lifetimeRegular: Double = 98
    }

    /// 早鸟价过期时间(发布后 3 个月)
    private let launchDate = Date()
    private let earlyBirdDays = 90
    private var isEarlyBird: Bool {
        Date().timeIntervalSince(launchDate) < Double(earlyBirdDays) * 86400
    }

    private var pricing: Pricing { Pricing() }

    private var lifetimePrice: Double {
        isEarlyBird ? pricing.lifetime : pricing.lifetimeRegular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    featureComparison
                    planPicker
                    purchaseButton
                }
                .padding(.bottom, 32)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color.cream.ignoresSafeArea())
            .onAppear {
                AnalyticsManager.shared.track(.paywallViewed, properties: ["source": "settings"])
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
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

            Text("升级高级版")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.sageDark)

            Text("解锁 AI 最佳推荐，更智能地管理照片")
                .font(.subheadline)
                .foregroundColor(.warmGray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    // MARK: - 功能对比

    private var featureComparison: some View {
        VStack(spacing: 0) {
            FeatureRow(feature: "重复照片检测", free: true, pro: true)
            Divider()
            FeatureRow(feature: "相似照片分组", free: true, pro: true)
            Divider()
            FeatureRow(feature: "截图识别", free: true, pro: true)
            Divider()
            FeatureRow(feature: "批量删除", free: true, pro: true)
            Divider()
            FeatureRow(feature: "最佳推荐（前3组预览）", free: true, pro: true)
            Divider()
            FeatureRow(feature: "最佳推荐（全量）", free: false, pro: true)
            Divider()
            FeatureRow(feature: "一键保留最佳", free: false, pro: true)
            Divider()
            FeatureRow(feature: "可解释推荐文案", free: true, pro: true)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - 方案选择

    private var planPicker: some View {
        VStack(spacing: 12) {
            Text("选择方案")
                .font(.headline)
                .foregroundColor(.sageDark)

            ForEach(PlanType.allCases, id: \.self) { plan in
                PlanCard(
                    plan: plan,
                    price: priceFor(plan),
                    period: periodFor(plan),
                    badge: badgeFor(plan),
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

    private func priceFor(_ plan: PlanType) -> String {
        switch plan {
        case .monthly: return "¥\(Int(pricing.monthly))"
        case .yearly: return "¥\(Int(pricing.yearly))"
        case .lifetime: return "¥\(Int(lifetimePrice))"
        }
    }

    private func periodFor(_ plan: PlanType) -> String {
        switch plan {
        case .monthly: return "/月"
        case .yearly: return "/年"
        case .lifetime: return " 永久"
        }
    }

    private func badgeFor(_ plan: PlanType) -> String? {
        switch plan {
        case .yearly: return "最受欢迎"
        case .lifetime: return isEarlyBird ? "早鸟价" : "限时"
        default: return nil
        }
    }

    // MARK: - 购买按钮

    private var purchaseButton: some View {
        VStack(spacing: 8) {
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

            Text("购买后自动续订，可随时取消")
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
        case .monthly: return "订阅 ¥\(Int(pricing.monthly))/月"
        case .yearly: return "订阅 ¥\(Int(pricing.yearly))/年（省 ¥\(Int(pricing.monthly * 12 - pricing.yearly))）"
        case .lifetime: return "买断 ¥\(Int(lifetimePrice))（一次购买，永久使用）"
        }
    }

    private func purchase() {
        catHaptic(.medium)
        AnalyticsManager.shared.track(
            .purchaseFailed,
            properties: ["plan": selectedPlan.rawValue, "price": priceFor(selectedPlan)]
        )
        alertMessage = "内测版暂未接入 App Store 支付，高级功能不会模拟解锁。"
        showAlert = true
    }

    private func restorePurchase() {
        AnalyticsManager.shared.track(.restorePurchaseClicked)
        alertMessage = "内测版暂未接入 App Store 恢复购买。"
        showAlert = true
    }
}

// MARK: - 功能行

struct FeatureRow: View {
    let feature: String
    let free: Bool
    let pro: Bool

    var body: some View {
        HStack {
            Text(feature)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 24) {
                Image(systemName: free ? "checkmark" : "xmark")
                    .foregroundColor(free ? .sage : .warmGray.opacity(0.4))
                    .frame(width: 24)

                Image(systemName: pro ? "checkmark" : "xmark")
                    .foregroundColor(pro ? .sageDark : .warmGray.opacity(0.4))
                    .frame(width: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 方案卡片

struct PlanCard: View {
    let plan: PaywallView.PlanType
    let price: String
    let period: String
    let badge: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(plan.rawValue)
                            .font(.headline)
                            .foregroundColor(.sageDark)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.sage)
                                .clipShape(Capsule())
                        }
                    }

                    Text(price + period)
                        .font(.subheadline)
                        .foregroundColor(.warmGray)
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
    }
}
