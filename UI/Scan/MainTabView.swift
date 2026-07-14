import SwiftUI

/// 主页面（扫描 + 结果，按年分桶版）
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner = PhotoScanner()
    @State private var showSettings = false

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
            if scanner.availableYears.isEmpty {
                scanner.detectAvailableYears()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch (oldPhase, newPhase) {
            case (.active, .inactive), (.active, .background):
                scanner.pauseForBackground()
            case (_, .active):
                scanner.resumeAfterForeground()
            default:
                break
            }
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
