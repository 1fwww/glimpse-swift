import Foundation
import CommonCrypto

/// Persists chat threads as JSON files.
/// Directory: ~/Library/Application Support/glimpse/threads/
/// Keeps only the 10 most recent threads.
class ThreadStore {
    let threadsDir: URL
    let imagesDir: URL
    private let maxThreads = 100

    init(appSupportDir: URL) {
        threadsDir = appSupportDir.appendingPathComponent("threads")
        imagesDir = appSupportDir.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: threadsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    /// Save a base64-encoded image to disk using content-addressed storage.
    /// Filename = SHA256 hash of image data. Same content → same file, no duplicates.
    /// Multiple threads can reference the same image path safely.
    func saveImage(threadId: String, messageIndex: Int, base64Data: String, mediaType: String) -> String? {
        guard let data = Data(base64Encoded: base64Data) else {
            NSLog("[ThreadStore] Failed to decode base64 image data")
            return nil
        }
        let ext = mediaType.contains("jpeg") ? "jpg" : "png"
        let hash = sha256Prefix(data)
        let filename = "\(hash).\(ext)"
        let fileURL = imagesDir.appendingPathComponent(filename)
        // Skip write if file with same hash already exists (idempotent)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL)
                NSLog("[ThreadStore] Saved image \(filename) (\(data.count / 1024)KB)")
            } catch {
                NSLog("[ThreadStore] Failed to save image: \(error)")
                return nil
            }
        }
        return "images/\(filename)"
    }

    /// First 16 chars of SHA256 hex digest — collision-safe for image dedup.
    private func sha256Prefix(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Delete image files not referenced by any live thread.
    private func deleteUnreferencedImages(excluding excludeThreadId: String) {
        // Collect all image paths referenced by remaining threads
        let fm = FileManager.default
        guard let threadFiles = try? fm.contentsOfDirectory(at: threadsDir, includingPropertiesForKeys: nil) else { return }
        var referencedPaths = Set<String>()
        for file in threadFiles where file.pathExtension == "json" {
            // Skip the thread being deleted (already removed from disk)
            if file.deletingPathExtension().lastPathComponent == excludeThreadId { continue }
            guard let data = try? Data(contentsOf: file),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = dict["messages"] as? [[String: Any]] else { continue }
            for msg in messages {
                guard let content = msg["content"] as? [[String: Any]] else { continue }
                for block in content {
                    if (block["type"] as? String) == "image",
                       let source = block["source"] as? [String: Any],
                       (source["type"] as? String) == "file",
                       let path = source["path"] as? String {
                        // Extract filename from "images/xxx.png"
                        referencedPaths.insert(URL(fileURLWithPath: path).lastPathComponent)
                    }
                }
            }
        }

        // Delete image files not referenced by any thread
        guard let imageFiles = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else { return }
        for file in imageFiles {
            let name = file.lastPathComponent
            if !referencedPaths.contains(name) {
                try? fm.removeItem(at: file)
                NSLog("[ThreadStore] Deleted unreferenced image \(name)")
            }
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
        // Delete images not referenced by any remaining thread
        deleteUnreferencedImages(excluding: id)
        return ["success": true]
    }

    /// Return all images across all threads, sorted by timestamp descending.
    /// Each entry: { path, threadId, threadTitle, messageIndex, timestamp, question, answer }
    func getAllImages() -> [[String: Any]] {
        let fm = FileManager.default
        // Read ALL thread files (not getThreads() which caps at maxThreads)
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
        var result: [[String: Any]] = []

        for thread in threads {
            guard let threadId = thread["id"] as? String,
                  let messages = thread["messages"] as? [[String: Any]] else { continue }
            let threadTitle = thread["title"] as? String ?? "Untitled"
            let threadTimestamp = (thread["updatedAt"] as? NSNumber)?.doubleValue ?? 0

            for (i, msg) in messages.enumerated() {
                guard (msg["role"] as? String) == "user",
                      let content = msg["content"] as? [[String: Any]] else { continue }

                // Find image block with file reference
                guard let imageBlock = content.first(where: { ($0["type"] as? String) == "image" }),
                      let source = imageBlock["source"] as? [String: Any],
                      (source["type"] as? String) == "file",
                      let path = source["path"] as? String else { continue }

                // Verify file exists on disk and get its creation time
                let fileURL = imagesDir.deletingLastPathComponent().appendingPathComponent(path)
                guard fm.fileExists(atPath: fileURL.path) else { continue }
                // Use image file modification time as the per-image timestamp
                let fileAttrs = try? fm.attributesOfItem(atPath: fileURL.path)
                let fileDate = fileAttrs?[.modificationDate] as? Date
                let timestamp = fileDate.map { $0.timeIntervalSince1970 * 1000 } ?? threadTimestamp

                // Extract question text from this message
                let question = content
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Extract answer from next assistant message
                var answer = ""
                if i + 1 < messages.count,
                   (messages[i + 1]["role"] as? String) == "assistant",
                   let nextContent = messages[i + 1]["content"] as? [[String: Any]] {
                    answer = nextContent
                        .filter { ($0["type"] as? String) == "text" }
                        .compactMap { $0["text"] as? String }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if answer.count > 200 {
                        answer = String(answer.prefix(200)) + "…"
                    }
                }

                result.append([
                    "path": path,
                    "threadId": threadId,
                    "threadTitle": threadTitle,
                    "messageIndex": i,
                    "timestamp": timestamp,
                    "question": question,
                    "answer": answer
                ])
            }
        }

        // Sort by timestamp descending (most recent first)
        result.sort { a, b in
            let aTime = (a["timestamp"] as? Double) ?? 0
            let bTime = (b["timestamp"] as? Double) ?? 0
            return aTime > bTime
        }

        // Deduplicate by image file path — same image referenced by multiple
        // threads appears once (content-addressed filenames make this natural).
        var seenPaths = Set<String>()
        result = result.filter { entry in
            guard let path = entry["path"] as? String else { return false }
            return seenPaths.insert(path).inserted
        }

        return result
    }

    /// Remove threads beyond maxThreads limit
    private func pruneOldThreads() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: threadsDir, includingPropertiesForKeys: nil) else { return }
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        guard jsonFiles.count > maxThreads else { return }

        // Reuse getThreads() for sort order, then delete anything not in the kept set
        let keptIDs = Set(getThreads().compactMap { $0["id"] as? String })
        var removedAny = false
        for file in jsonFiles {
            let id = file.deletingPathExtension().lastPathComponent
            if !keptIDs.contains(id) {
                try? fm.removeItem(at: file)
                removedAny = true
            }
        }
        if removedAny {
            deleteUnreferencedImages(excluding: "")
        }
    }
}
