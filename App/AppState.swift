import SwiftUI
import Photos

/// 全局应用状态管理
final class AppState: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var scanState: ScanState = .idle
    @Published var scanProgress: ScanProgress = .zero
    @Published var scanResults: ScanResults?
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "has_completed_onboarding") }
    }
    @Published var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: "is_pro") }
    }
    @Published var isAnalyticsOptedOut: Bool {
        didSet { AnalyticsManager.shared.isOptedOut = isAnalyticsOptedOut }
    }

    // MARK: - 试用机制

    /// 试用开始时间。首次完成 onboarding 时写入，nil = 尚未开始试用
    @Published var trialStartDate: Date? {
        didSet {
            if let date = trialStartDate {
                UserDefaults.standard.set(date, forKey: "trial_start_date")
            }
        }
    }

    /// 购买类型（用于区分订阅/买断）
    @Published var purchaseType: PurchaseType {
        didSet { UserDefaults.standard.set(purchaseType.rawValue, forKey: "purchase_type") }
    }

    enum PurchaseType: String {
        case none
        case monthly
        case yearly
        case lifetime
    }

    /// 试用天数
    private let trialDurationDays: Double = 7

    /// 试用是否仍在有效期内
    /// 注：`trialStartDate == nil`（老版本升级/未触发 onboarding）时，为了避免"既没开始试用又直接锁死"
    /// 的第三种状态，init 里已自动补写 `trialStartDate = Date()`，这里不再额外处理。
    var isTrialActive: Bool {
        guard let start = trialStartDate else { return true }
        return Date().timeIntervalSince(start) < trialDurationDays * 86400
    }

    /// 试用剩余天数（向上取整，0 表示已到期）
    var trialDaysRemaining: Int {
        guard let start = trialStartDate else { return Int(trialDurationDays) }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = trialDurationDays * 86400 - elapsed
        return remaining > 0 ? Int(ceil(remaining / 86400)) : 0
    }

    /// 试用是否已过期（明确开始过试用且已到期，不含"从未开始试用"的状态）
    var isTrialExpired: Bool {
        guard let start = trialStartDate else { return false }
        return Date().timeIntervalSince(start) >= trialDurationDays * 86400
    }

    /// 是否拥有完整功能权限（付费或试用期内）
    var hasFullAccess: Bool {
        isPro || isTrialActive
    }

    /// 功能是否被锁定（非付费且试用明确到期）
    var isFeatureLocked: Bool {
        // 兜底：即使用户在未来出现某种不一致状态也不能"锁死"。
        // 只要不是「明确 isPro == false 且试用已明确过期」，都视为全可用。
        guard !isPro else { return false }
        return isTrialExpired
    }

    /// 开始试用（onboarding 完成时调用）
    func startTrial() {
        guard trialStartDate == nil else { return }
        trialStartDate = Date()
    }

    /// 完成购买
    func completePurchase(type: PurchaseType) {
        purchaseType = type
        isPro = true
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        self.isPro = UserDefaults.standard.bool(forKey: "is_pro")
        self.isAnalyticsOptedOut = AnalyticsManager.shared.isOptedOut
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let persistedStartDate = UserDefaults.standard.object(forKey: "trial_start_date") as? Date
        let raw = UserDefaults.standard.string(forKey: "purchase_type") ?? PurchaseType.none.rawValue
        self.purchaseType = PurchaseType(rawValue: raw) ?? .none

        // 2026-08-28 修复：老版本升级的用户已经完成 onboarding，但还没有写过 trial_start_date，
        // 会落入"试用既未开始又直接锁死"的第三种状态，立刻弹付费墙，与"首周 7 天免费试用"承诺不符。
        // 做法：如果已经完成 onboarding 且没有 trialStartDate，则按"今天是试用第一天"处理。
        if self.hasCompletedOnboarding && persistedStartDate == nil && !self.isPro {
            let newStart = Date()
            UserDefaults.standard.set(newStart, forKey: "trial_start_date")
            self.trialStartDate = newStart
        } else {
            self.trialStartDate = persistedStartDate
        }
    }
}

enum ScanState: Equatable {
    case idle
    case scanning
    case completed
    case error(String)
}

struct ScanProgress {
    var current: Int = 0
    var total: Int = 0

    static let zero = ScanProgress()

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    var formatted: String {
        "\(current) / \(total)"
    }
}
