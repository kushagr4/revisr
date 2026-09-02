import Foundation

enum ZIPArchiveError: LocalizedError {
    case invalidEntryName(String)
    case archiveTooLarge
    case malformedArchive

    var errorDescription: String? {
        switch self {
        case let .invalidEntryName(name): "Invalid ZIP entry name: \(name)"
        case .archiveTooLarge: "The export is too large to package."
        case .malformedArchive: "The generated ZIP archive is malformed."
        }
    }
}

/// A small standards-compliant ZIP writer using the STORE method. Export data
/// is already compact text, so avoiding an additional compression dependency
/// keeps private local export reproducible and auditable.
enum ZIPArchiveWriter {
    struct Entry: Equatable, Sendable {
        let name: String
        let data: Data
    }

    static func makeArchive(entries: [Entry], modifiedAt: Date) throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw ZIPArchiveError.archiveTooLarge }
        var output = Data()
        var centralRecords: [(entry: Entry, crc: UInt32, offset: UInt32)] = []
        let (dosTime, dosDate) = dosTimestamp(modifiedAt)

        for entry in entries.sorted(by: { $0.name < $1.name }) {
            try validate(name: entry.name)
            let nameData = Data(entry.name.utf8)
            guard nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  output.count <= Int(UInt32.max) else {
                throw ZIPArchiveError.archiveTooLarge
            }
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(output.count)
            output.appendLittleEndian(UInt32(0x04034b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0x0800)) // UTF-8 names
            output.appendLittleEndian(UInt16(0)) // STORE
            output.appendLittleEndian(dosTime)
            output.appendLittleEndian(dosDate)
            output.appendLittleEndian(crc)
            output.appendLittleEndian(UInt32(entry.data.count))
            output.appendLittleEndian(UInt32(entry.data.count))
            output.appendLittleEndian(UInt16(nameData.count))
            output.appendLittleEndian(UInt16(0))
            output.append(nameData)
            output.append(entry.data)
            centralRecords.append((entry, crc, offset))
        }

        guard output.count <= Int(UInt32.max) else { throw ZIPArchiveError.archiveTooLarge }
        let centralOffset = UInt32(output.count)
        for record in centralRecords {
            let nameData = Data(record.entry.name.utf8)
            output.appendLittleEndian(UInt32(0x02014b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0x0800))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(dosTime)
            output.appendLittleEndian(dosDate)
            output.appendLittleEndian(record.crc)
            output.appendLittleEndian(UInt32(record.entry.data.count))
            output.appendLittleEndian(UInt32(record.entry.data.count))
            output.appendLittleEndian(UInt16(nameData.count))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt32(0))
            output.appendLittleEndian(record.offset)
            output.append(nameData)
        }
        guard output.count <= Int(UInt32.max) else { throw ZIPArchiveError.archiveTooLarge }
        let centralSize = UInt32(output.count) - centralOffset
        output.appendLittleEndian(UInt32(0x06054b50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(centralRecords.count))
        output.appendLittleEndian(UInt16(centralRecords.count))
        output.appendLittleEndian(centralSize)
        output.appendLittleEndian(centralOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    /// Used by validation/tests to prove the package has the intended entries
    /// without extracting user data to another directory.
    static func entryNames(in archive: Data) throws -> [String] {
        try entries(in: archive).map(\.name)
    }

    /// Reads STORE entries directly for validation and tests. Revisr only writes
    /// uncompressed entries, so this deliberately rejects any other method.
    static func entries(in archive: Data) throws -> [Entry] {
        guard archive.count >= 22 else { throw ZIPArchiveError.malformedArchive }
        let signature = Data([0x50, 0x4b, 0x05, 0x06])
        let searchStart = max(0, archive.count - 65_557)
        guard let eocdRange = archive.range(
            of: signature,
            options: .backwards,
            in: searchStart..<archive.count
        ) else { throw ZIPArchiveError.malformedArchive }
        let eocd = eocdRange.lowerBound
        let count = Int(try archive.uint16(at: eocd + 10))
        var cursor = Int(try archive.uint32(at: eocd + 16))
        var entries: [Entry] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard try archive.uint32(at: cursor) == 0x02014b50 else {
                throw ZIPArchiveError.malformedArchive
            }
            let compressionMethod = try archive.uint16(at: cursor + 10)
            guard compressionMethod == 0 else { throw ZIPArchiveError.malformedArchive }
            let compressedSize = Int(try archive.uint32(at: cursor + 20))
            let uncompressedSize = Int(try archive.uint32(at: cursor + 24))
            let nameLength = Int(try archive.uint16(at: cursor + 28))
            let extraLength = Int(try archive.uint16(at: cursor + 30))
            let commentLength = Int(try archive.uint16(at: cursor + 32))
            let localOffset = Int(try archive.uint32(at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= archive.count,
                  let name = String(data: archive[nameStart..<nameEnd], encoding: .utf8) else {
                throw ZIPArchiveError.malformedArchive
            }
            guard try archive.uint32(at: localOffset) == 0x04034b50 else {
                throw ZIPArchiveError.malformedArchive
            }
            let localNameLength = Int(try archive.uint16(at: localOffset + 26))
            let localExtraLength = Int(try archive.uint16(at: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            let dataEnd = dataStart + compressedSize
            guard compressedSize == uncompressedSize,
                  dataStart >= 0,
                  dataEnd <= archive.count else {
                throw ZIPArchiveError.malformedArchive
            }
            entries.append(Entry(name: name, data: Data(archive[dataStart..<dataEnd])))
            cursor = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func validate(name: String) throws {
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.split(separator: "/").contains(".."),
              !name.contains("\\") else {
            throw ZIPArchiveError.invalidEntryName(name)
        }
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(2107, max(1980, components.year ?? 1980))
        let month = min(12, max(1, components.month ?? 1))
        let day = min(31, max(1, components.day ?? 1))
        let hour = min(23, max(0, components.hour ?? 0))
        let minute = min(59, max(0, components.minute ?? 0))
        let second = min(59, max(0, components.second ?? 0))
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let date = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, date)
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }

    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? 0xedb8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ZIPArchiveError.malformedArchive }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ZIPArchiveError.malformedArchive }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
