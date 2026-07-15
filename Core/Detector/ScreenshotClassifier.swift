import Foundation
import UIKit
import Vision

/// 截图内容分类
enum ScreenshotCategory: String, CaseIterable, Hashable {
    case sensitiveDocument = "敏感证件"
    case smsCode = "短信验证码"
    case verificationCode = "验证码"
    case receipt = "收据发票"
    case chatHistory = "聊天记录"
    case webCapture = "网页截屏"
    case appUI = "应用界面"
    case ordinary = "普通截图"

    /// 受保护分类：不可被推荐删除
    var isProtected: Bool { self == .sensitiveDocument }

    /// 一次性内容：超过有效期后建议删除
    var isDisposable: Bool { self == .smsCode || self == .verificationCode }

    /// 一次性截图的有效期（秒），超期视为可安全删除
    var expiry: TimeInterval {
        switch self {
        case .smsCode: return 24 * 3600       // 短信验证码 24 小时后可删
        case .verificationCode: return 7 * 24 * 3600  // 普通验证码 7 天后可删
        default: return 0
        }
    }

    var icon: String {
        switch self {
        case .sensitiveDocument: return "lock.shield"
        case .smsCode: return "message.badge"
        case .verificationCode: return "lock"
        case .receipt: return "doc.text"
        case .chatHistory: return "bubble.left"
        case .webCapture: return "safari"
        case .appUI: return "app"
        case .ordinary: return "photo"
        }
    }
}

/// 截图内容分类器：OCR + 规则匹配
enum ScreenshotClassifier {

    /// 对截图进行 OCR 并分类
    static func classify(image: UIImage, creationDate: Date?) async -> ScreenshotCategory {
        guard let cgImage = image.cgImage else { return .ordinary }

        let text = await recognizeText(in: cgImage)
        guard !text.isEmpty else { return .ordinary }

        return matchCategory(text: text, creationDate: creationDate)
    }

    /// 判断一次性截图是否已过期（可安全删除）
    static func isExpired(_ category: ScreenshotCategory, creationDate: Date?) -> Bool {
        guard category.isDisposable, let creationDate else { return false }
        return Date().timeIntervalSince(creationDate) > category.expiry
    }

    // MARK: - OCR

    private static func recognizeText(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
                return
            }

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            continuation.resume(returning: text)
        }
    }

    // MARK: - 规则匹配（按优先级）

    private static func matchCategory(text: String, creationDate: Date?) -> ScreenshotCategory {
        let lower = text.lowercased()

        // 1. 敏感证件（最高优先级：保护优先于一切）
        if SensitiveDocumentPatterns.contains(where: { text.contains($0) }) {
            return .sensitiveDocument
        }

        // 2. 短信验证码（含短信来源特征 + 验证码关键词/数字串）
        if isSMSCode(text, lower) {
            return .smsCode
        }

        // 3. 收据发票（优先于泛验证码，避免订单号/金额误判为验证码）
        if ReceiptKeywords.contains(where: { text.contains($0) }) {
            return .receipt
        }

        // 4. 聊天记录（优先于泛验证码，避免聊天里的数字误判）
        if ChatKeywords.contains(where: { text.contains($0) }) {
            return .chatHistory
        }

        // 5. 网页截屏（优先于泛验证码，避免网页编号误判）
        if WebPatterns.contains(where: { lower.contains($0) }) {
            return .webCapture
        }

        // 6. 普通验证码（必须关键词 + 数字串同时命中，避免单纯数字误判）
        //    收据/聊天/网页已在前置步骤消费掉含数字的内容
        if VerificationCodeKeywords.contains(where: { lower.contains($0) }),
           hasStandaloneDigits(text) {
            return .verificationCode
        }

        // 7. 应用界面（导航栏/标签栏特征词，且无其他分类命中）
        if AppUIKeywords.contains(where: { text.contains($0) }) {
            return .appUI
        }

        return .ordinary
    }

    // MARK: - 规则细节

    private static let SensitiveDocumentPatterns = [
        "身份证", "护照", "驾驶证", "行驶证", "银行卡", "社保卡",
        "港澳通行证", "出生证", "结婚证", "营业执照", "学位证",
        "证件号码", "有效期限", "签发机关"
    ]

    private static let VerificationCodeKeywords = [
        "验证码", "verification code", "security code", "otp", "pin code"
    ]

    private static let ReceiptKeywords = [
        "发票", "收据", "订单", "金额", "合计", "小票", "账单",
        "付款", "支付", "退款", "订单号", "交易号", "消费", "应收"
    ]

    private static let ChatKeywords = [
        "微信", "QQ", "聊天", "消息", "发送", "语音", "通讯录",
        "朋友圈", "公众号", "小程序", "群聊", "对方", "我"
    ]

    private static let WebPatterns = [
        "http://", "https://", "www.", ".com", ".cn", ".net", ".org",
        "safari", "chrome", "edge", "浏览器", "搜索或输入网址"
    ]

    private static let AppUIKeywords = [
        "返回", "取消", "完成", "编辑", "设置", "确定", "下一步",
        "首页", "我的", "发现", "消息", "通讯录", "搜索"
    ]

    /// 短信验证码：同时含短信来源特征和验证码关键词/数字串
    private static func isSMSCode(_ text: String, _ lower: String) -> Bool {
        let hasSMSSource = text.contains("【") && text.contains("】")  // 【XX科技】格式
            || text.contains("短信")
            || lower.contains("sms")

        let hasCode = VerificationCodeKeywords.contains(where: { lower.contains($0) })
            || hasStandaloneDigits(text)

        return hasSMSSource && hasCode
    }

    /// 检测独立的 4-8 位数字串（验证码常见格式）
    private static func hasStandaloneDigits(_ text: String) -> Bool {
        let pattern = "\\b\\d{4,8}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
