import SwiftUI
import UIKit
import Photos

/// 设置页面（奶油白配色）
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    /// 用户打开系统设置后切回前台，用来刷新授权状态文案
    @State private var refreshToken: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // 高级会员
                Section {
                    HStack {
                        Image(systemName: appState.isPro ? "sparkles" : "crown")
                            .foregroundColor(appState.isPro ? .sage : .warmGray)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.isPro ? "高级会员" : "免费用户")
                                .font(.headline)
                            Text(appState.isPro ? "全部功能已解锁" : "升级解锁更多功能")
                                .font(.caption)
                                .foregroundColor(.warmGray)
                        }
                        
                        Spacer()
                        
                        if !appState.isPro {
                            Button("升级") {
                                showPaywall = true
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.brandGradient)
                            .clipShape(Capsule())
                        }
                    }
                }
                
                // 权限与隐私（合并为一个 section，避免相册权限/管理相册权限两个入口的冲突）
                Section {
                    // 唯一入口：相册权限。
                    // 系统限制下不能直接在 App 内修改授权状态，所以行为分两种：
                    // - 从未弹过授权（notDetermined）：立即拉起系统授权弹窗，用户原地改完就生效；
                    // - 其它所有状态（已授权/受限/拒绝/部分照片）：直接跳到「设置 → 轻猫」页，
                    //   用户可以在那里改照片权限、开关网络等所有权限项。
                    Button(action: tapPhotoPermission) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundColor(.sage)
                            Text("相册权限")
                            Spacer()
                            Text(permissionStatusText)
                                .font(.caption)
                                .foregroundColor(.warmGray)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.warmGray)
                        }
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text("权限与隐私")
                } footer: {
                    Text("iOS 不允许 App 内直接修改相册权限，未授权时会立即弹出系统授权；已修改过的状态会跳到「设置 → 轻猫」页修改。")
                }

                Section {
                    Toggle(isOn: $appState.isAnalyticsOptedOut) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("关闭诊断数据")
                            Text("关闭后，轻猫不会写入本地使用日志")
                                .font(.caption)
                                .foregroundColor(.warmGray)
                        }
                    }
                }
                
                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.warmGray)
                    }
                }
                
                // 反馈
                Section {
                    Button(action: sendFeedback) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.peach)
                            Text("发送反馈")
                            Spacer()
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        catHaptic(.light)
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("关闭设置")
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "settings")
                    .environmentObject(appState)
            }
            // 强制 sheet 下滑关闭有效
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
            // 从系统设置回到 App，刷新授权文案
            .onChange(of: refreshToken, initial: false) { _, _ in
                appState.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshToken.toggle()
            }
        }
    }

    // MARK: - 相册权限（唯一入口）

    /// 相册权限文案，展示在按钮右侧。
    private var permissionStatusText: String {
        switch appState.authorizationStatus {
        case .notDetermined: return "未设置"
        case .authorized:    return "所有照片"
        case .limited:       return "部分照片"
        case .denied:        return "拒绝访问"
        case .restricted:    return "受系统限制"
        @unknown default:    return "未知"
        }
    }

    /// 点击「相册权限」后的统一行为。
    ///
    /// - .notDetermined：立即拉起系统授权弹窗；
    /// - 其它状态：直接跳到「设置 → 轻猫」页。
    /// 不做"你已经授权了所以不用改"的反问反馈，用户想检查权限就是合理诉求。
    private func tapPhotoPermission() {
        catHaptic(.medium)
        switch appState.authorizationStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    appState.authorizationStatus = newStatus
                }
            }
        case .authorized, .limited, .denied, .restricted:
            openAppSystemSettings()
        @unknown default:
            openAppSystemSettings()
        }
    }

    /// 跳转到 iOS 「设置 → 轻猫」页。
    ///
    /// - 只用官方 `UIApplication.openSettingsURLString`（`app-settings:` scheme），
    ///   绝不调用 `app-prefs:` / `prefs:root=` 私有 scheme（会报 LSApplicationWorkspaceError 115）；
    /// - **不要用 `canOpenURL` 预检**：对 `app-settings:` 这类系统 scheme，`canOpenURL` 在真机上会返回
    ///   false（且需要在 Info.plist 的 LSApplicationQueriesSchemes 声明），反而会把真正能打开的动作拦掉。
    ///   官方 scheme 直接 `open` 即可。
    private func openAppSystemSettings() {
        catHaptic(.light)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            #if DEBUG
            NSLog("[Settings] 无法构造系统设置 URL")
            #endif
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            #if DEBUG
            if !success {
                NSLog("[Settings] openURL 未成功: \(url.absoluteString)")
            }
            #endif
        }
    }

    // MARK: - 反馈

    private func sendFeedback() {
        // TODO: 集成反馈功能
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return "1.0.0"
        }
    }
}
