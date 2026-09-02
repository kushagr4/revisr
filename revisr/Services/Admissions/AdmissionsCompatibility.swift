import Foundation

enum CanonicalStringArrayCodec {
    static func encode<S: Sequence>(_ values: S) -> String where S.Element == String {
        let canonical = Array(Set(values)).sorted()
        let data = try? JSONEncoder().encode(canonical)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func decode(_ rawValue: String?) -> [String]? {
        guard let rawValue, let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        return Array(Set(values)).sorted()
    }
}

enum PreparationStreamCompatibility {
    static func encode(_ streams: some Sequence<PreparationStreamKind>) -> String {
        CanonicalStringArrayCodec.encode(streams.map(\.rawValue))
    }

    static func decode(_ rawValue: String?) -> Set<PreparationStreamKind>? {
        guard let values = CanonicalStringArrayCodec.decode(rawValue) else { return nil }
        let streams = values.compactMap(PreparationStreamKind.init(rawValue:))
        guard streams.count == values.count else { return nil }
        return Set(streams)
    }

    static func legacyFallback(for test: AdmissionsTestKind) -> Set<PreparationStreamKind> {
        switch test {
        case .tmua: [.tmua]
        case .csat: [.csat]
        }
    }
}

struct DuplicateIdentityRecord: Equatable, Sendable {
    let stableID: String
    let binaryChecksum: String?
    let normalizedTextChecksum: String?
    let verifiedSemanticIdentity: String?
    let verifiedQuestionIdentity: String?
}

enum DuplicateIdentityResolver {
    /// Returns an existing canonical identity only for deterministic evidence.
    /// Filename or fuzzy similarity is deliberately not accepted here.
    static func canonicalRecord(
        for candidate: DuplicateIdentityRecord,
        among existing: [DuplicateIdentityRecord]
    ) -> DuplicateIdentityRecord? {
        existing.sorted { $0.stableID < $1.stableID }.first { record in
            exactMatch(candidate.binaryChecksum, record.binaryChecksum)
                || exactMatch(candidate.normalizedTextChecksum, record.normalizedTextChecksum)
                || exactMatch(candidate.verifiedSemanticIdentity, record.verifiedSemanticIdentity)
                || exactMatch(candidate.verifiedQuestionIdentity, record.verifiedQuestionIdentity)
        }
    }

    private static func exactMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalized(lhs), let rhs = normalized(rhs) else { return false }
        return lhs == rhs
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
