import Foundation

public enum SHIORIEventFactory {
    public static func firstBoot(vanishCount: Int) -> GhostEvent {
        .shiori(id: "OnFirstBoot", references: [0: String(vanishCount)])
    }

    public static func boot(shellName: String) -> GhostEvent {
        .shiori(id: "OnBoot", references: [0: shellName])
    }

    public static func ghostChanged(
        previousCharacterName: String,
        previousScript: String,
        previousGhostName: String,
        previousGhostPath: String,
        shellName: String
    ) -> GhostEvent {
        .shiori(id: "OnGhostChanged", references: [
            0: previousCharacterName,
            1: previousScript,
            2: previousGhostName,
            3: previousGhostPath,
            7: shellName
        ])
    }

    public static func ghostChanging(
        characterName: String,
        mode: String,
        ghostName: String,
        ghostPath: String
    ) -> GhostEvent {
        .shiori(id: "OnGhostChanging", references: [
            0: characterName,
            1: mode,
            2: ghostName,
            3: ghostPath
        ])
    }

    public static func ghostCalled(
        callerCharacterName: String,
        callerScript: String,
        callerGhostName: String,
        callerGhostPath: String,
        shellName: String
    ) -> GhostEvent {
        .shiori(id: "OnGhostCalled", references: [
            0: callerCharacterName,
            1: callerScript,
            2: callerGhostName,
            3: callerGhostPath,
            7: shellName
        ])
    }

    public static func ghostCalling(
        characterName: String,
        mode: String,
        ghostName: String,
        ghostPath: String
    ) -> GhostEvent {
        .shiori(id: "OnGhostCalling", references: [
            0: characterName,
            1: mode,
            2: ghostName,
            3: ghostPath
        ])
    }

    public static func ghostCallComplete(
        characterName: String,
        startupScript: String,
        ghostName: String,
        shellName: String
    ) -> GhostEvent {
        .shiori(id: "OnGhostCallComplete", references: [
            0: characterName,
            1: startupScript,
            2: ghostName,
            7: shellName
        ])
    }

    public static func otherGhostBooted(
        characterName: String,
        startupScript: String,
        ghostName: String,
        shellName: String
    ) -> GhostEvent {
        .shiori(id: "OnOtherGhostBooted", references: [
            0: characterName,
            1: startupScript,
            2: ghostName,
            7: shellName
        ])
    }

    public static func otherGhostClosed(
        characterName: String,
        finalScript: String,
        ghostName: String,
        shellName: String
    ) -> GhostEvent {
        .shiori(id: "OnOtherGhostClosed", references: [
            0: characterName,
            1: finalScript,
            2: ghostName,
            7: shellName
        ])
    }

    public static func vanished(
        characterName: String,
        vanishScript: String,
        ghostName: String,
        shellName: String
    ) -> GhostEvent {
        .shiori(id: "OnVanished", references: [
            0: characterName,
            1: vanishScript,
            2: ghostName,
            7: shellName
        ])
    }

    public static func shellChanging(
        newShellName: String,
        previousShellName: String,
        newShellPath: String
    ) -> GhostEvent {
        .shiori(id: "OnShellChanging", references: [
            0: newShellName,
            1: previousShellName,
            2: newShellPath
        ])
    }

    public static func shellChanged(
        shellName: String,
        ghostName: String,
        shellPath: String
    ) -> GhostEvent {
        .shiori(id: "OnShellChanged", references: [
            0: shellName,
            1: ghostName,
            2: shellPath
        ])
    }

    public static func textDrop(_ text: String, scope: Int) -> GhostEvent {
        .shiori(id: "OnTextDrop", references: [
            0: text.replacingOccurrences(of: "\n", with: "\u{1}"),
            1: String(scope)
        ])
    }

    public static let communicateInputCancel = GhostEvent.shiori(
        id: "OnCommunicateInputCancel",
        references: [0: "", 1: "cancel"]
    )

    public static let teachStart = GhostEvent.shiori(id: "OnTeachStart", references: [:])

    public static let teachInputCancel = GhostEvent.shiori(
        id: "OnTeachInputCancel",
        references: [0: "", 1: "cancel"]
    )

    public static func teach(history: [String]) -> GhostEvent {
        .shiori(id: "OnTeach", references: Dictionary(
            uniqueKeysWithValues: history.enumerated().map { ($0.offset, $0.element) }
        ))
    }

    public static func updateProcessExec(reason: String) -> GhostEvent {
        .shiori(id: "OnUpdateProcessExec", references: [0: reason])
    }

    public static func updateBegin(
        name: String,
        path: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateBegin", references: [
            0: name,
            1: path,
            3: updateType,
            4: reason
        ])
    }

    public static func updateReady(
        files: [String],
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateReady", references: [
            0: String(max(0, files.count - 1)),
            1: files.joined(separator: ","),
            3: updateType,
            4: reason
        ])
    }

    public static func updateComplete(
        changedFiles: [String],
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateComplete", references: [
            0: changedFiles.isEmpty ? "none" : "changed",
            1: changedFiles.joined(separator: ","),
            3: updateType,
            4: reason
        ])
    }

    public static func updateFailure(
        failureReason: String,
        failurePath: String?,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateFailure", references: [
            0: failureReason,
            1: failurePath ?? "",
            3: updateType,
            4: reason
        ])
    }

    public static func updateDownloadBegin(
        path: String,
        index: Int,
        total: Int,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdate.OnDownloadBegin", references: [
            0: path,
            1: String(index),
            2: String(max(0, total - 1)),
            3: updateType,
            4: reason
        ])
    }

    public static func updateMD5CompareBegin(
        path: String,
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        updateMD5CompareEvent(
            id: "OnUpdate.OnMD5CompareBegin",
            path: path,
            expected: expected,
            actual: actual,
            updateType: updateType,
            reason: reason
        )
    }

    public static func updateMD5CompareComplete(
        path: String,
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        updateMD5CompareEvent(
            id: "OnUpdate.OnMD5CompareComplete",
            path: path,
            expected: expected,
            actual: actual,
            updateType: updateType,
            reason: reason
        )
    }

    public static func updateMD5CompareFailure(
        path: String,
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        updateMD5CompareEvent(
            id: "OnUpdate.OnMD5CompareFailure",
            path: path,
            expected: expected,
            actual: actual,
            updateType: updateType,
            reason: reason
        )
    }

    public static func updateOtherBegin(
        name: String,
        path: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateOtherBegin", references: [
            0: name,
            1: path,
            3: updateType,
            4: reason
        ])
    }

    public static func updateOtherReady(
        files: [String],
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateOtherReady", references: [
            0: String(max(0, files.count - 1)),
            1: files.joined(separator: ","),
            3: updateType,
            4: reason
        ])
    }

    public static func updateOtherComplete(
        changedFiles: [String],
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateOtherComplete", references: [
            0: changedFiles.isEmpty ? "none" : "changed",
            1: changedFiles.joined(separator: ","),
            3: updateType,
            4: reason
        ])
    }

    public static func updateOtherFailure(
        failureReason: String,
        failurePath: String?,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateOtherFailure", references: [
            0: failureReason,
            1: failurePath ?? "",
            3: updateType,
            4: reason
        ])
    }

    public static func updateOtherDownloadBegin(
        path: String,
        index: Int,
        total: Int,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateOther.OnDownloadBegin", references: [
            0: path,
            1: String(index),
            2: String(max(0, total - 1)),
            3: updateType,
            4: reason
        ])
    }

    public static func updateOtherMD5CompareBegin(
        path: String,
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateOther.OnMD5CompareBegin", references: [
            0: path,
            1: expected,
            2: actual,
            3: updateType,
            4: reason
        ])
    }

    public static func updateOtherMD5CompareComplete(
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        updateOtherMD5CompareResult(
            id: "OnUpdateOther.OnMD5CompareComplete",
            expected: expected,
            actual: actual,
            updateType: updateType,
            reason: reason
        )
    }

    public static func updateOtherMD5CompareFailure(
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        updateOtherMD5CompareResult(
            id: "OnUpdateOther.OnMD5CompareFailure",
            expected: expected,
            actual: actual,
            updateType: updateType,
            reason: reason
        )
    }

    public static func updateCheckComplete(
        changedFiles: [String],
        updateType: String
    ) -> GhostEvent {
        .shiori(id: "OnUpdateCheckComplete", references: [
            0: changedFiles.isEmpty ? "none" : "changed",
            1: changedFiles.joined(separator: ","),
            3: updateType,
            4: "script"
        ])
    }

    public static func updateCheckFailure(failureReason: String) -> GhostEvent {
        .shiori(id: "OnUpdateCheckFailure", references: [
            0: failureReason,
            4: "script"
        ])
    }

    public static func updateResultExtended(records: [String], checkOnly: Bool) -> GhostEvent {
        .shiori(
            id: checkOnly ? "OnUpdateCheckResultEx" : "OnUpdateResultEx",
            references: indexedReferences(records)
        )
    }

    public static func updateResultLegacy(records: [String], checkOnly: Bool) -> GhostEvent {
        .shiori(
            id: checkOnly ? "OnUpdateCheckResult" : "OnUpdateResult",
            references: indexedReferences(records)
        )
    }

    public static func updateResultExplorer(records: [String]) -> GhostEvent {
        .shiori(
            id: "OnUpdateResultExplorer",
            references: indexedReferences(records)
        )
    }

    public static func recommendsiteChoice(
        title: String,
        target: String,
        banner: String,
        kind: String,
        scope: Int,
        index: Int
    ) -> GhostEvent {
        .shiori(id: "OnRecommendsiteChoice", references: [
            0: title,
            1: target,
            2: banner,
            3: kind,
            4: String(scope),
            5: String(index)
        ])
    }

    public static func anchorSelectExtended(
        label: String,
        id: String,
        arguments: [String]
    ) -> GhostEvent {
        .shiori(
            id: "OnAnchorSelectEx",
            references: indexedReferences([label, id] + arguments)
        )
    }

    public static func anchorSelect(id: String) -> GhostEvent {
        .shiori(id: "OnAnchorSelect", references: [0: id])
    }

    public static func choiceSelectExtended(
        label: String,
        id: String,
        arguments: [String]
    ) -> GhostEvent {
        .shiori(
            id: "OnChoiceSelectEx",
            references: indexedReferences([label, id] + arguments)
        )
    }

    public static func choiceSelect(id: String, arguments: [String]) -> GhostEvent {
        .choice(id: id, arguments: arguments)
    }

    public static func balloonChange(name: String, path: String) -> GhostEvent {
        .shiori(id: "OnBalloonChange", references: [0: name, 1: path])
    }

    public static func nsLookup(
        id: String,
        eventLabel: String,
        host: String,
        reverse: Bool,
        result: String?
    ) -> GhostEvent {
        var references = [
            0: eventLabel,
            1: host,
            2: reverse ? "reverse" : "lookup"
        ]
        if let result, !result.isEmpty {
            references[3] = result
        }
        return .shiori(id: id, references: references)
    }

    public static func headlinesenseBegin(name: String, url: String) -> GhostEvent {
        .shiori(id: "OnHeadlinesenseBegin", references: [0: name, 1: url])
    }

    public static func headlinesenseFind(
        name: String,
        url: String,
        phase: String,
        headline: String
    ) -> GhostEvent {
        .shiori(id: "OnHeadlinesense.OnFind", references: [
            0: name,
            1: url,
            2: phase,
            3: headline
        ])
    }

    public static let headlinesenseComplete = GhostEvent.shiori(
        id: "OnHeadlinesenseComplete",
        references: [0: "no update"]
    )

    public static func headlinesenseFailure(reason: String) -> GhostEvent {
        .shiori(id: "OnHeadlinesenseFailure", references: [0: reason])
    }

    public static func rssBegin(name: String, url: String) -> GhostEvent {
        .shiori(id: "OnRSSBegin", references: [0: name, 1: url])
    }

    public static func rssComplete(references: [Int: String]) -> GhostEvent {
        .shiori(id: "OnRSSComplete", references: references)
    }

    public static let rssNoUpdate = GhostEvent.shiori(
        id: "OnRSSComplete",
        references: [0: "no update"]
    )

    public static func rssFailure(reason: String) -> GhostEvent {
        .shiori(id: "OnRSSFailure", references: [0: reason])
    }

    public static func executeHTTPComplete(
        eventID: String,
        method: String,
        url: String,
        result: String,
        statusCode: String,
        cookie: String,
        headers: String
    ) -> GhostEvent {
        executeHTTPResult(
            id: executionEventID(defaultID: "OnExecuteHTTPComplete", eventID: eventID),
            eventID: eventID,
            method: method,
            url: url,
            result: result,
            statusCode: statusCode,
            cookie: cookie,
            headers: headers
        )
    }

    public static func executeHTTPFailure(
        eventID: String,
        method: String,
        url: String,
        result: String = "",
        reason: String,
        cookie: String = "",
        headers: String = ""
    ) -> GhostEvent {
        executeHTTPResult(
            id: executionEventID(defaultID: "OnExecuteHTTPFailure", eventID: eventID, isFailure: true),
            eventID: eventID,
            method: method,
            url: url,
            result: result,
            statusCode: reason,
            cookie: cookie,
            headers: headers
        )
    }

    public static func executeRSSComplete(eventID: String, records: [String]) -> GhostEvent {
        .shiori(
            id: executionEventID(defaultID: "OnExecuteRSSComplete", eventID: eventID),
            references: Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.offset, $0.element) })
        )
    }

    public static func executeRSSFailure(
        eventID: String,
        method: String,
        url: String,
        reason: String,
        cookie: String = "",
        headers: String = ""
    ) -> GhostEvent {
        executeHTTPResult(
            id: executionEventID(defaultID: "OnExecuteRSSFailure", eventID: eventID, isFailure: true),
            eventID: eventID,
            method: method,
            url: url,
            result: "",
            statusCode: reason,
            cookie: cookie,
            headers: headers
        )
    }

    public static func sntpBegin(server: String) -> GhostEvent {
        .shiori(id: "OnSNTPBegin", references: [0: server])
    }

    public static func sntpCompareExtended(references: [Int: String]) -> GhostEvent {
        .shiori(id: "OnSNTPCompareEx", references: references)
    }

    public static func sntpCompare(references: [Int: String]) -> GhostEvent {
        .shiori(id: "OnSNTPCompare", references: references)
    }

    public static func sntpFailure(server: String) -> GhostEvent {
        .shiori(id: "OnSNTPFailure", references: [0: server])
    }

    public static func extractArchiveComplete(
        eventID: String,
        fileCount: Int,
        compressedBytes: Int,
        uncompressedBytes: Int
    ) -> GhostEvent {
        archiveComplete(
            defaultID: "OnExtractArchiveComplete",
            eventID: eventID,
            fileCount: fileCount,
            compressedBytes: compressedBytes,
            uncompressedBytes: uncompressedBytes
        )
    }

    public static func extractArchiveFailure(eventID: String, reason: String) -> GhostEvent {
        archiveFailure(defaultID: "OnExtractArchiveFailure", eventID: eventID, reason: reason)
    }

    public static func compressArchiveComplete(
        eventID: String,
        fileCount: Int,
        compressedBytes: Int,
        uncompressedBytes: Int
    ) -> GhostEvent {
        archiveComplete(
            defaultID: "OnCompressArchiveComplete",
            eventID: eventID,
            fileCount: fileCount,
            compressedBytes: compressedBytes,
            uncompressedBytes: uncompressedBytes
        )
    }

    public static func compressArchiveFailure(eventID: String, reason: String) -> GhostEvent {
        archiveFailure(defaultID: "OnCompressArchiveFailure", eventID: eventID, reason: reason)
    }

    private static func updateMD5CompareEvent(
        id: String,
        path: String,
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: id, references: [
            0: path,
            1: expected,
            2: actual,
            3: updateType,
            4: reason
        ])
    }

    private static func updateOtherMD5CompareResult(
        id: String,
        expected: String,
        actual: String,
        updateType: String,
        reason: String
    ) -> GhostEvent {
        .shiori(id: id, references: [
            1: expected,
            2: actual,
            3: updateType,
            4: reason
        ])
    }

    private static func indexedReferences(_ values: [String]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset, $0.element) })
    }

    private static func archiveComplete(
        defaultID: String,
        eventID: String,
        fileCount: Int,
        compressedBytes: Int,
        uncompressedBytes: Int
    ) -> GhostEvent {
        .shiori(id: eventID.hasPrefix("On") ? eventID : defaultID, references: [
            0: eventID,
            1: String(fileCount),
            2: String(compressedBytes),
            3: String(uncompressedBytes)
        ])
    }

    private static func archiveFailure(defaultID: String, eventID: String, reason: String) -> GhostEvent {
        .shiori(
            id: eventID.hasPrefix("On") ? "\(eventID)Failure" : defaultID,
            references: [0: eventID, 1: reason]
        )
    }

    private static func executeHTTPResult(
        id: String,
        eventID: String,
        method: String,
        url: String,
        result: String,
        statusCode: String,
        cookie: String,
        headers: String
    ) -> GhostEvent {
        .shiori(id: id, references: [
            0: method.lowercased(),
            1: eventID,
            2: url,
            3: result,
            4: statusCode,
            5: cookie,
            6: headers
        ])
    }

    private static func executionEventID(defaultID: String, eventID: String, isFailure: Bool = false) -> String {
        guard eventID.hasPrefix("On") else {
            return defaultID
        }
        return isFailure ? "\(eventID)Failure" : eventID
    }
}
