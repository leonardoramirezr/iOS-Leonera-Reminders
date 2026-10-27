import Foundation

extension UUID {
    /// A UUID that is always the same for the same `key` (two 64-bit FNV-1a lanes with different seeds).
    ///
    /// Not cryptographic: it only gives each scheduled alarm an identity that can be recomputed on every sync,
    /// so nothing has to be stored to know which alarms already exist.
    init(stableFrom key: String) {
        let bytes = Array(key.utf8)
        let high = Self.fnv1a(bytes, seed: 0xcbf2_9ce4_8422_2325)
        let low = Self.fnv1a(bytes, seed: 0x8422_2325_cbf2_9ce4)
        var raw = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            raw[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(index)))
            raw[index + 8] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(index)))
        }
        // Version 8 (custom) and the RFC 4122 variant, so it is a well-formed UUID.
        raw[6] = (raw[6] & 0x0f) | 0x80
        raw[8] = (raw[8] & 0x3f) | 0x80
        self.init(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
