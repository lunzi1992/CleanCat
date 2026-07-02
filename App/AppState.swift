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
    
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        self.isPro = UserDefaults.standard.bool(forKey: "is_pro")
        self.isAnalyticsOptedOut = AnalyticsManager.shared.isOptedOut
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
