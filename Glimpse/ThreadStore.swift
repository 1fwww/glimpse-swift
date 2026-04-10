import Foundation

/// Persists chat threads as JSON files.
/// Directory: ~/Library/Application Support/glimpse/threads/
/// Keeps only the 5 most recent threads.
class ThreadStore {
    let threadsDir: URL
    private let maxThreads = 5

    init(appSupportDir: URL) {
        threadsDir = appSupportDir.appendingPathComponent("threads")
        try? FileManager.default.createDirectory(at: threadsDir, withIntermediateDirectories: true)
    }

    func getThreads() -> [[String: Any]] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: threadsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var threads: [[String: Any]] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                threads.append(dict)
            }
        }

        // Sort by updatedAt descending
        threads.sort { a, b in
            let aTime = a["updatedAt"] as? String ?? ""
            let bTime = b["updatedAt"] as? String ?? ""
            return aTime > bTime
        }

        // Keep only maxThreads
        return Array(threads.prefix(maxThreads))
    }

    func saveThread(_ thread: [String: Any]) -> [String: Any] {
        guard let id = thread["id"] as? String else {
            return ["success": false, "error": "Missing thread id"]
        }

        let fileURL = threadsDir.appendingPathComponent("\(id).json")
        if let data = try? JSONSerialization.data(withJSONObject: thread, options: .prettyPrinted) {
            do {
                try data.write(to: fileURL)
                pruneOldThreads()
                return ["success": true]
            } catch {
                return ["success": false, "error": error.localizedDescription]
            }
        }
        return ["success": false, "error": "Failed to serialize thread"]
    }

    func deleteThread(id: String) -> [String: Any] {
        let fileURL = threadsDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: fileURL)
        return ["success": true]
    }

    /// Remove threads beyond maxThreads limit
    private func pruneOldThreads() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: threadsDir, includingPropertiesForKeys: nil) else { return }

        var threadFiles: [(url: URL, updatedAt: String)] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let updatedAt = dict["updatedAt"] as? String {
                threadFiles.append((file, updatedAt))
            }
        }

        threadFiles.sort { $0.updatedAt > $1.updatedAt }

        if threadFiles.count > maxThreads {
            for file in threadFiles[maxThreads...] {
                try? fm.removeItem(at: file.url)
            }
        }
    }
}
