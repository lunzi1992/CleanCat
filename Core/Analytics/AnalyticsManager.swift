import Foundation
import UIKit

/// 埋点系统 (PRD V1.1 §8)
/// - 28 个事件覆盖主漏斗骨架 + 4 阶段领先指标
/// - 7 个通用属性维度支撑分群与漏斗分析
/// - V1.0 阶段先本地日志,后续可对接第三方 (Firebase / Sentry / 自建)
final class AnalyticsManager {
    static let shared = AnalyticsManager()
    static let optOutKey = "opt_out_analytics"

    private let queue = DispatchQueue(label: "com.cleancat.analytics", qos: .utility)
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 用户级别匿名 ID (安装后稳定)
    private lazy var anonId: String = {
        if let saved = UserDefaults.standard.string(forKey: "anon_id") {
            return saved
        }
        let new = "a_" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(new, forKey: "anon_id")
        return new
    }()

    private init() {
        Self.removeLegacyDocumentLog()
    }

    /// 相册规模分桶
    enum PhotoLibrarySizeBucket: String {
        case empty = "empty"
        case small = "<1k"
        case medium = "1k-5k"
        case large = "5k-10k"
        case xlarge = "10k-30k"
        case xxlarge = ">30k"

        static func from(_ count: Int) -> PhotoLibrarySizeBucket {
            switch count {
            case 0: return .empty
            case 1..<1000: return .small
            case 1000..<5000: return .medium
            case 5000..<10000: return .large
            case 10000..<30000: return .xlarge
            default: return .xxlarge
            }
        }
    }

    /// 通用属性(自动附加到所有事件)
    struct CommonProperties {
        let userId: String? = nil
        let anonId: String
        let appVersion: String
        let deviceModel: String
        let iosVersion: String
        let photoLibrarySizeBucket: String
        let sessionId: String
        let isFirstSession: Bool
        let timeToEventMs: Int?

        static func current(bucket: String? = nil, isFirstSession: Bool = false, timeSinceLaunchMs: Int? = nil) -> CommonProperties {
            let device = UIDevice.current
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
            let model = device.model
            let iosVer = device.systemVersion
            return CommonProperties(
                anonId: AnalyticsManager.shared.anonId,
                appVersion: appVersion,
                deviceModel: model,
                iosVersion: iosVer,
                photoLibrarySizeBucket: bucket ?? "unknown",
                sessionId: SessionTracker.shared.currentSessionId,
                isFirstSession: isFirstSession,
                timeToEventMs: timeSinceLaunchMs
            )
        }
    }

    // MARK: - 事件定义(PRD §8.2)

    enum Event: String {
        // 启动
        case appFirstLaunch = "app_first_launch"
        case appReopen = "app_reopen"

        // Onboarding
        case onboardingViewed = "onboarding_viewed"
        case onboardingCompleted = "onboarding_completed"
        case onboardingSkipped = "onboarding_skipped"

        // 权限
        case permissionRequested = "permission_requested"
        case permissionGranted = "permission_granted"
        case permissionDenied = "permission_denied"

        // 扫描
        case scanStarted = "scan_started"
        case scanProgress = "scan_progress"
        case scanCompleted = "scan_completed"
        case scanCancelled = "scan_cancelled"
        case scanPaused = "scan_paused"
        case scanResumed = "scan_resumed"
        case scanFailed = "scan_failed"

        // 结果页
        case resultPageViewed = "result_page_viewed"
        case resultTabSwitched = "result_tab_switched"
        case resultEmptyViewed = "result_empty_viewed"
        case photoSelected = "photo_selected"
        case photoDeselected = "photo_deselected"
        case photoSelectAllTapped = "photo_select_all_tapped"

        // 删除
        case deleteConfirmed = "delete_confirmed"
        case deleteCompleted = "delete_completed"
        case deleteCancelled = "delete_cancelled"

        // 付费
        case paywallViewed = "paywall_viewed"
        case paywallDismissed = "paywall_dismissed"
        case paywallPlanSelected = "paywall_plan_selected"
        case purchaseCompleted = "purchase_completed"
        case purchaseFailed = "purchase_failed"
        case purchaseCancelled = "purchase_cancelled"
        case restorePurchaseClicked = "restore_purchase_clicked"

        // 留存
        case rescanTriggered = "rescan_triggered"
    }

    // MARK: - 上报接口

    var isOptedOut: Bool {
        get { UserDefaults.standard.bool(forKey: Self.optOutKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.optOutKey)
            if newValue {
                queue.async {
                    Self.purgeLocalLogs()
                }
            }
        }
    }

    /// 上报事件
    /// - Parameters:
    ///   - event: 事件名
    ///   - properties: 事件专属属性
    ///   - bucket: 相册规模分桶(可选)
    func track(
        _ event: Event,
        properties: [String: Any] = [:],
        bucket: PhotoLibrarySizeBucket? = nil,
        isFirstSession: Bool = false
    ) {
        guard !isOptedOut else { return }

        let timeSinceLaunch = SessionTracker.shared.millisecondsSinceLaunch
        let common = CommonProperties.current(
            bucket: bucket?.rawValue,
            isFirstSession: isFirstSession,
            timeSinceLaunchMs: timeSinceLaunch
        )

        var payload: [String: Any] = [
            "event": event.rawValue,
            "timestamp": dateFormatter.string(from: Date()),
            "anon_id": common.anonId,
            "app_version": common.appVersion,
            "device_model": common.deviceModel,
            "ios_version": common.iosVersion,
            "photo_library_size_bucket": common.photoLibrarySizeBucket,
            "session_id": common.sessionId,
            "is_first_session": common.isFirstSession
        ]
        if let ms = common.timeToEventMs {
            payload["time_to_event_ms"] = ms
        }
        // 合并事件属性
        for (k, v) in properties {
            payload["prop_\(k)"] = v
        }

        // 异步写日志,不阻塞主线程
        queue.async { [payload] in
            Self.writeToLog(payload)
        }
    }

    /// 简易事件上报(无相册分桶)
    func track(_ event: Event, properties: [String: Any] = [:]) {
        track(event, properties: properties, bucket: nil, isFirstSession: SessionTracker.shared.isFirstSession)
    }

    // MARK: - 持久化(本地日志,V1.0 阶段)

    private static func writeToLog(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let line = String(data: data, encoding: .utf8) ?? ""

        // 输出到控制台(Debug 模式)
        #if DEBUG
        print("[Analytics] \(line)")
        #endif

        // 追加写入本地日志文件(便于后续上报或调试)
        let logURL = logFileURL()
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            if let lineData = (line + "\n").data(using: .utf8) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: lineData)
            }
        } else {
            try? (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private static func logFileURL() -> URL {
        let manager = FileManager.default
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = caches.appendingPathComponent("Analytics", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("analytics.log")
    }

    private static func purgeLocalLogs() {
        let manager = FileManager.default
        try? manager.removeItem(at: logFileURL())
        if let legacyURL = legacyDocumentLogURL() {
            try? manager.removeItem(at: legacyURL)
        }
    }

    private static func removeLegacyDocumentLog() {
        guard let legacyURL = legacyDocumentLogURL() else { return }
        try? FileManager.default.removeItem(at: legacyURL)
    }

    private static func legacyDocumentLogURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("analytics.log")
    }
}

// MARK: - 会话追踪

final class SessionTracker {
    static let shared = SessionTracker()

    private let launchTimestamp: Date = Date()
    private(set) var currentSessionId: String = "s_" + UUID().uuidString.lowercased()
    private let firstSession: Bool

    var isFirstSession: Bool {
        firstSession
    }

    var millisecondsSinceLaunch: Int {
        Int(Date().timeIntervalSince(launchTimestamp) * 1000)
    }

    private init() {
        firstSession = !UserDefaults.standard.bool(forKey: "has_launched_before")
        UserDefaults.standard.set(true, forKey: "has_launched_before")
    }
}
