import Foundation

/// Persists chat threads as JSON files.
/// Directory: ~/Library/Application Support/glimpse/threads/
/// Keeps only the 10 most recent threads.
class ThreadStore {
    let threadsDir: URL
    let imagesDir: URL
    private let maxThreads = 10

    init(appSupportDir: URL) {
        threadsDir = appSupportDir.appendingPathComponent("threads")
        imagesDir = appSupportDir.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: threadsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    /// Save a base64-encoded image to disk. Returns relative path (e.g. "images/abc_0.png") or nil on failure.
    func saveImage(threadId: String, messageIndex: Int, base64Data: String, mediaType: String) -> String? {
        guard let data = Data(base64Encoded: base64Data) else {
            NSLog("[ThreadStore] Failed to decode base64 image data")
            return nil
        }
        let ext = mediaType.contains("jpeg") ? "jpg" : "png"
        let filename = "\(threadId)_\(messageIndex).\(ext)"
        let fileURL = imagesDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            NSLog("[ThreadStore] Saved image \(filename) (\(data.count / 1024)KB)")
            return "images/\(filename)"
        } catch {
            NSLog("[ThreadStore] Failed to save image: \(error)")
            return nil
        }
    }

    /// Delete all images associated with a thread ID.
    private func deleteImages(forThreadId id: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else { return }
        let prefix = "\(id)_"
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: file)
            NSLog("[ThreadStore] Deleted image \(file.lastPathComponent)")
        }
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

        // Sort by updatedAt descending (JS sends Date.now() = milliseconds number)
        threads.sort { a, b in
            let aTime = (a["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            let bTime = (b["updatedAt"] as? NSNumber)?.doubleValue ?? 0
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
        deleteImages(forThreadId: id)
        return ["success": true]
    }

    /// Remove threads beyond maxThreads limit
    private func pruneOldThreads() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: threadsDir, includingPropertiesForKeys: nil) else { return }
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        guard jsonFiles.count > maxThreads else { return }

        // Reuse getThreads() for sort order, then delete anything not in the kept set
        let keptIDs = Set(getThreads().compactMap { $0["id"] as? String })
        for file in jsonFiles {
            let id = file.deletingPathExtension().lastPathComponent
            if !keptIDs.contains(id) {
                try? fm.removeItem(at: file)
                deleteImages(forThreadId: id)
            }
        }
    }
}
