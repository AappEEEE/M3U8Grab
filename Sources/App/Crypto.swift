import Foundation
import CommonCrypto

enum Crypto {
    enum CryptoError: LocalizedError {
        case aesFailed(Int32)

        var errorDescription: String? {
            switch self {
            case let .aesFailed(status): return "AES 解密失败（CCCrypt \(status)）"
            }
        }
    }

    /// HLS 的 AES-128：CBC 模式、单分片独立 PKCS7 填充。
    static func aes128CBCDecrypt(_ payload: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, !payload.isEmpty else {
            throw CryptoError.aesFailed(-1)
        }
        var ivBytes = [UInt8](iv.prefix(kCCBlockSizeAES128))
        if ivBytes.count < kCCBlockSizeAES128 {
            ivBytes.append(contentsOf: [UInt8](repeating: 0, count: kCCBlockSizeAES128 - ivBytes.count))
        }
        let capacity = payload.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: capacity)
        var moved = 0

        let status = payload.withUnsafeBytes { payloadBytes -> Int32 in
            key.withUnsafeBytes { keyBytes -> Int32 in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(0),
                    keyBytes.baseAddress, key.count,
                    ivBytes,
                    payloadBytes.baseAddress, payload.count,
                    &output, capacity,
                    &moved
                )
            }
        }
        guard status == kCCSuccess else { throw CryptoError.aesFailed(status) }
        let decrypted = Data(output.prefix(moved))
        return stripPKCS7(decrypted)
    }

    static func stripPKCS7(_ data: Data) -> Data {
        guard let last = data.last else { return data }
        let pad = Int(last)
        guard pad >= 1, pad <= kCCBlockSizeAES128, pad <= data.count else { return data }
        let tail = data.suffix(pad)
        guard tail.allSatisfy({ $0 == last }) else { return data }
        return data.prefix(data.count - pad)
    }
}
