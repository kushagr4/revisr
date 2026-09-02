import Foundation

/// Temporary, opt-in physical-device profiling. The final hotfix is built
/// without HOTFIX_PROFILE, so this records nothing in production.
enum PerformanceProbe {
#if HOTFIX_PROFILE
    private static let queue = DispatchQueue(label: "com.kushagra.revisr.performance-probe")
    private static let lock = NSLock()
    private static var starts: [String: UInt64] = [:]

    static func measure<Value>(_ name: String, _ operation: () throws -> Value) rethrows -> Value {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = try operation()
        record(name, durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started)
        return value
    }

    static func begin(_ name: String) {
        lock.lock()
        starts[name] = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

    static func end(_ name: String) {
        lock.lock()
        let started = starts.removeValue(forKey: name)
        lock.unlock()
        guard let started else { return }
        record(name, durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started)
    }

    static func tick(_ name: String) {
        record(name, durationNanoseconds: 0)
    }

    private static func record(_ name: String, durationNanoseconds: UInt64) {
        let milliseconds = Double(durationNanoseconds) / 1_000_000
        let timestamp = Date().timeIntervalSince1970
        queue.async {
            let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
            let line = "{\"name\":\"\(escapedName)\",\"milliseconds\":\(milliseconds),\"timestamp\":\(timestamp)}\n"
            guard let data = line.data(using: .utf8) else { return }
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let url = directory.appendingPathComponent("RevisrPerformanceProfile.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
#else
    static func measure<Value>(_ name: String, _ operation: () throws -> Value) rethrows -> Value {
        try operation()
    }
    static func begin(_ name: String) {}
    static func end(_ name: String) {}
    static func tick(_ name: String) {}
#endif
}
