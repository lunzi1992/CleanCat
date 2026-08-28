import SwiftUI

/// 主页面（扫描 + 结果，按年分桶版）
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scanner: PhotoScanner
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var previousScenePhase: ScenePhase = .active
    /// 防止 onAppear 因为前后台切换多次触发，重复"自动开始扫描"。
    @State private var hasTriggeredAutoScan = false

    var body: some View {
        ZStack {
            Group {
                switch scanner.state {
                case .idle:
                    ScanStartView(scanner: scanner)
                case .scanning:
                    ScanningView(scanner: scanner)
                case .completed:
                    if let results = scanner.currentResults {
                        ResultsView(results: results, scanner: scanner)
                    } else {
                        ScanStartView(scanner: scanner)
                    }
                case .error(let message):
                    ScanErrorView(message: message, scanner: scanner)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                settingsButton
            }
            .padding(.trailing, Design.contentHorizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .allowsHitTesting(true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .onAppear {
            // 真机上从 Onboarding → 授权成功 → 首次进入主页面，这里需要在检测到最新一年后自动开始扫描。
            // 自动扫描只在「尚未触发过自动扫描 + 当前没有扫描结果」时执行；
            // 其它情况（用户已有之前的结果、用户从后台切回、或切换页面导致 onAppear 重走）一律不自动开扫。
            scanner.detectAvailableYears(preferLatestIfUnset: true) { [hasTriggeredAutoScan] in
                guard !hasTriggeredAutoScan else { return }
                guard case .idle = scanner.state else { return }
                guard scanner.yearResults.isEmpty else { return }
                guard scanner.selectedBucket != nil else { return }
                self.hasTriggeredAutoScan = true
                scanner.scanSelected()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch (previousScenePhase, newPhase) {
            case (.active, .inactive), (.active, .background):
                scanner.pauseForBackground()
            case (_, .active):
                scanner.resumeAfterForeground()
            default:
                break
            }
            previousScenePhase = newPhase
        }
    }

    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.sageDark)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.sage.opacity(0.14), lineWidth: 1)
                )
        }
        .accessibilityLabel("设置")
    }
}
