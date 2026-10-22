import CPrivate
import Foundation
import IOKit

/// Membaca key dari AppleSMC. Koneksi dibuka sekali, info tiap key di-cache.
public final class SMCReader {
    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: SMCKeyInfo] = [:]

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, UInt32(kSMCHandleYPCEvent),
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private func info(for key: UInt32) -> SMCKeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = key
        input.data8 = UInt8(kSMCGetKeyInfo)
        guard let output = call(input) else { return nil }
        infoCache[key] = output.keyInfo
        return output.keyInfo
    }

    /// Nilai mentah sebuah key beserta tipenya (mis. "flt ", "ui32").
    public func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        let code = fourCC(key)
        guard let info = info(for: code) else { return nil }
        var input = SMCParamStruct()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(kSMCReadKey)
        guard let output = call(input) else { return nil }
        let size = min(Int(info.dataSize), 32)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        return (string(from: info.dataType), bytes)
    }

    /// Nilai numerik sebuah key, untuk tipe yang umum dipakai sensor.
    public func readDouble(_ key: String) -> Double? {
        guard let (type, bytes) = readRaw(key) else { return nil }
        switch type {
        case "flt " where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    public func keyCount() -> Int {
        Int(readDouble("#KEY") ?? 0)
    }

    public func key(at index: Int) -> String? {
        var input = SMCParamStruct()
        input.data8 = UInt8(kSMCGetKeyFromIndex)
        input.data32 = UInt32(index)
        guard let output = call(input) else { return nil }
        return string(from: output.key)
    }

    public func allKeys() -> [String] {
        (0..<keyCount()).compactMap { key(at: $0) }
    }

    private func fourCC(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private func string(from code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
