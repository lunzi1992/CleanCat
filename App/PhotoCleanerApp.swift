import SwiftUI

@main
struct CleanCatApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 启动事件
        AnalyticsManager.shared.track(
            .appFirstLaunch,
            isFirstSession: SessionTracker.shared.isFirstSession
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.none)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && SessionTracker.shared.millisecondsSinceLaunch > 1000 {
                        // 非首次启动的 active 状态 = app_reopen
                        AnalyticsManager.shared.track(.appReopen)
                    }
                }
        }
    }
}
