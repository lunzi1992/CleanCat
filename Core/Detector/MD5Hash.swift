import Foundation
import CryptoKit

/// MD5 哈希工具
enum MD5Hash {
    static func compute(from data: Data) -> String {
        hexString(from: Insecure.MD5.hash(data: data))
    }

    static func hexString<D: Sequence>(from digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
