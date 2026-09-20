import Darwin
import Foundation
import UtataneCore
import UtataneSakuraScript

@MainActor
final class SakuraScriptFileWatchManager {
    private struct Watch {
        let source: DispatchSourceFileSystemObject
        var debounceTask: Task<Void, Never>?
        let requestedPath: String
        let targetURL: URL
        let watchesDirectory: Bool
        let eventID: String?
        let debounceMilliseconds: Int
        var existed: Bool
        var modificationDate: Date?
    }

    private var watches: [String: Watch] = [:]

    func handle(
        _ command: SakuraScriptFileWatchCommand,
        masterDirectory: URL,
        notify: @escaping @MainActor (GhostEvent) -> Void
    ) -> GhostEvent? {
        switch command {
        case let .cancel(path):
            cancel(path: normalized(path, masterDirectory: masterDirectory).path)
            return nil
        case let .start(path, eventID, debounceMilliseconds):
            let target = normalized(path, masterDirectory: masterDirectory)
            let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let watchesDirectory = values?.isDirectory == true
            let watchedURL = watchesDirectory ? target : target.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: watchedURL.path) else {
                return failure(path: path, eventID: eventID, reason: "notfound")
            }
            let descriptor = open(watchedURL.path, O_EVTONLY)
            guard descriptor >= 0 else { return failure(path: path, eventID: eventID, reason: "notfound") }
            cancel(path: target.path)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: .main
            )
            let existed = FileManager.default.fileExists(atPath: target.path)
            let watch = Watch(
                source: source,
                requestedPath: path,
                targetURL: target,
                watchesDirectory: watchesDirectory,
                eventID: eventID,
                debounceMilliseconds: max(0, debounceMilliseconds),
                existed: existed,
                modificationDate: values?.contentModificationDate
            )
            source.setCancelHandler { close(descriptor) }
            source.setEventHandler { [weak self] in
                guard let self else { return }
                scheduleNotification(for: target.path, notify: notify)
            }
            watches[target.path] = watch
            source.resume()
            return nil
        }
    }

    func cancelAll() {
        for key in Array(watches.keys) {
            cancel(path: key)
        }
    }

    private func scheduleNotification(for key: String, notify: @escaping @MainActor (GhostEvent) -> Void) {
        guard var watch = watches[key] else { return }
        watch.debounceTask?.cancel()
        let delay = watch.debounceMilliseconds
        watch.debounceTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.emitChange(for: key, notify: notify)
        }
        watches[key] = watch
    }

    private func emitChange(for key: String, notify: @escaping @MainActor (GhostEvent) -> Void) {
        guard var watch = watches[key] else { return }
        let parent = watch.targetURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else {
            notify(failure(path: watch.requestedPath, eventID: watch.eventID, reason: "notfound"))
            cancel(path: key)
            return
        }
        let exists = FileManager.default.fileExists(atPath: watch.targetURL.path)
        let values = try? watch.targetURL.resourceValues(forKeys: [.contentModificationDateKey])
        if !watch.watchesDirectory, watch.existed, exists,
           values?.contentModificationDate == watch.modificationDate
        {
            return
        }
        let change: String = if watch.watchesDirectory {
            exists ? "changed" : "deleted"
        } else if !watch.existed, exists {
            "created"
        } else if watch.existed, !exists {
            "deleted"
        } else {
            "modified"
        }
        watch.existed = exists
        watch.modificationDate = values?.contentModificationDate
        watches[key] = watch
        let id = watch.eventID?.hasPrefix("On") == true ? watch.eventID! : "OnExecuteFileWatchChange"
        notify(.shiori(id: id, references: [
            0: watch.eventID ?? "",
            1: watch.requestedPath,
            2: change,
            3: watch.targetURL.path
        ]))
        if !exists, watch.watchesDirectory {
            notify(failure(path: watch.requestedPath, eventID: watch.eventID, reason: "notfound"))
            cancel(path: key)
        }
    }

    private func failure(path: String, eventID: String?, reason: String) -> GhostEvent {
        let id = eventID?.hasPrefix("On") == true ? eventID! + "Failure" : "OnExecuteFileWatchFailure"
        return .shiori(id: id, references: [0: eventID ?? "", 1: path, 2: reason])
    }

    private func normalized(_ path: String, masterDirectory: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : masterDirectory.appending(path: path))
            .standardizedFileURL
    }

    private func cancel(path: String) {
        guard let watch = watches.removeValue(forKey: path) else { return }
        watch.debounceTask?.cancel()
        watch.source.cancel()
    }
}
