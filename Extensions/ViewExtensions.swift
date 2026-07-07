import SwiftUI

// MARK: - 轻猫品牌色系
// 奶油白 + 鼠尾草绿 + 蜜桃色 + 暖灰
// 去刻板化设计，温暖但不甜腻

extension Color {
    static let cream   = Color(red: 0.99, green: 0.97, blue: 0.94)
    static let sage    = Color(red: 0.53, green: 0.66, blue: 0.58)
    static let sageL   = Color(red: 0.88, green: 0.93, blue: 0.89)
    static let sageD   = Color(red: 0.35, green: 0.48, blue: 0.40)
    static let peach   = Color(red: 0.98, green: 0.85, blue: 0.78)
    static let peachL  = Color(red: 0.99, green: 0.93, blue: 0.90)
    static let grayW   = Color(red: 0.62, green: 0.60, blue: 0.58)
    static let appDanger = Color(red: 0.86, green: 0.43, blue: 0.43)
    static let warmGray = grayW
    static let sageLight = sageL
    static let sageDark = sageD
    static let peachLight = peachL

    static var bgGradient: LinearGradient {
        LinearGradient(colors: [.cream, sageL.opacity(0.6)], startPoint: .top, endPoint: .bottom)
    }
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [sage, sageD], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var warmGradient: LinearGradient {
        LinearGradient(colors: [cream, peachL.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 设计 Token 常量

enum Design {
    static let radiusXS: CGFloat = 10
    static let radiusSM: CGFloat = 16
    static let radiusMD: CGFloat = 20
    static let radiusLG: CGFloat = 24
    static let radiusXL: CGFloat = 32
    static let radiusFull: CGFloat = 999

    static let spaceXS: CGFloat = 8
    static let spaceSM: CGFloat = 12
    static let spaceMD: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static let spaceXL: CGFloat = 32
    static let space2XL: CGFloat = 48

    static let shadowColor = Color.black.opacity(0.06)
    static let shadowRadiusSm: CGFloat = 8
    static let shadowRadiusMd: CGFloat = 16
    static let shadowY: CGFloat = 4

    static let titleFont: Font = .system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont: Font = .system(size: 22, weight: .semibold, design: .rounded)
    static let bodyFont: Font = .system(size: 16, weight: .regular, design: .rounded)
    static let captionFont: Font = .system(size: 13, weight: .regular, design: .rounded)

    static let contentMaxWidth: CGFloat = 480
    static let contentHorizontalPadding: CGFloat = 20
}

// MARK: - 通用 ViewModifier

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Design.radiusSM))
            .shadow(color: Design.shadowColor, radius: Design.shadowRadiusSm, y: Design.shadowY)
    }
}

struct ElevatedCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Design.radiusSM))
            .shadow(color: Design.shadowColor, radius: Design.shadowRadiusMd, y: Design.shadowY)
    }
}

struct BrandButton: ViewModifier {
    let disabled: Bool
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: Design.contentMaxWidth)
            .padding(.vertical, 18)
            .background(Color.brandGradient.opacity(disabled ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Design.radiusFull))
    }
}

struct ContentWrapper: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Design.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Design.contentHorizontalPadding)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
    func elevatedCard() -> some View { modifier(ElevatedCard()) }
    func brandButton(disabled: Bool = false) -> some View { modifier(BrandButton(disabled: disabled)) }
    func contentWrapper() -> some View { modifier(ContentWrapper()) }

    @ViewBuilder
    func `if`<Content: View>(_ cond: Bool, @ViewBuilder t: (Self) -> Content) -> some View {
        if cond { t(self) } else { self }
    }
}

// MARK: - 猫爪触觉

func catImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

func catNotify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    UINotificationFeedbackGenerator().notificationOccurred(type)
}

// 兼容旧调用
func catHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    catImpact(style)
}
