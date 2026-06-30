import SwiftUI

/// 根视图：根据授权状态和引导完成状态决定显示哪个页面
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else {
                switch appState.authorizationStatus {
                case .notDetermined:
                    PermissionRequestView()
                case .authorized, .limited:
                    MainTabView()
                case .denied, .restricted:
                    PermissionDeniedView()
                @unknown default:
                    PermissionRequestView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.3), value: appState.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: appState.authorizationStatus)
    }
}
