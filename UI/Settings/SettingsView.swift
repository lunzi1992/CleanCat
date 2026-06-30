import SwiftUI
import UIKit

/// 设置页面（奶油白配色）
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false
    
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
                
                // 权限管理
                Section("权限") {
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundColor(.sage)
                            Text("相册权限")
                            Spacer()
                            Text(appState.authorizationStatus == .authorized ? "已授权" : "受限")
                                .foregroundColor(.warmGray)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.warmGray)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.warmGray)
                    }
                    
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.sage)
                            Text("隐私政策")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundColor(.warmGray)
                        }
                        .foregroundColor(.primary)
                    }
                    
                    Link(destination: URL(string: "https://example.com/terms")!) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.sage)
                            Text("使用条款")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundColor(.warmGray)
                        }
                        .foregroundColor(.primary)
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
    
    private func openSettings() {
        catHaptic(.light)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    private func sendFeedback() {
        // TODO: 集成反馈功能
    }
}
