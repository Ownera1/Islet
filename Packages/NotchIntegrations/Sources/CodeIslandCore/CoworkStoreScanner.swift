import Foundation

/// What the island needs to know about one Cowork session. Sent from the
/// helper to the app as JSON whenever it changes.
public struct CoworkSessionUpdate: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case idle, processing, waitingApproval, waitingQuestion
    }

    /// `local_<id>`, Claude Desktop's own session id.
    public var sessionId: String
    public var title: String?
    /// Host folder the user granted; the in-VM cwd means nothing on the Mac.
    public var cwd: String?
    public var phase: Phase
    public var currentTool: String?
    /// Command, path or question of the current tool or permission card.
    public var toolDetail: String?
    public var lastPrompt: String?
    public var lastResultText: String?
    public var lastActivity: Date
    /// The CLI session id inside the VM — what a hook-driven card would be keyed by.
    public var cliSessionId: String?
    public var completedTurnCount: Int
    /// A turn finished during this read. Never set for history read on first
    /// sight or after the file was replaced, so a restart cannot re-announce
    /// an old completion.
    public var turnEnded: Bool
    public var lastTurnInterrupted: Bool
    public var lastTurnFailed: Bool
    /// The session was archived, hidden or deleted: drop its card.
    public var removed: Bool

    public init(
        sessionId: String,
        title: String? = nil,
        cwd: String? = nil,
        phase: Phase = .idle,
        currentTool: String? = nil,
        toolDetail: String? = nil,
        lastPrompt: String? = nil,
        lastResultText: String? = nil,
        lastActivity: Date = Date(),
        cliSessionId: String? = nil,
        completedTurnCount: Int = 0,
        turnEnded: Bool = false,
        lastTurnInterrupted: Bool = false,
        lastTurnFailed: Bool = false,
        removed: Bool = false
    ) {
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.phase = phase
        self.currentTool = currentTool
        self.toolDetail = toolDetail
        self.lastPrompt = lastPrompt
        self.lastResultText = lastResultText
        self.lastActivity = lastActivity
        self.cliSessionId = cliSessionId
        self.completedTurnCount = completedTurnCount
        self.turnEnded = turnEnded
        self.lastTurnInterrupted = lastTurnInterrupted
        self.lastTurnFailed = lastTurnFailed
        self.removed = removed
    }

    public static func removal(sessionId: String) -> Self {
        Self(sessionId: sessionId, lastActivity: Date(timeIntervalSince1970: 0), removed: true)
    }
}

/// Polls Claude Desktop's Cowork store (`CoworkPaths`) and turns it into
/// `CoworkSessionUpdate`s. Read-only: it lists directories, stats files and
/// reads `local_<id>.json` and `audit.jsonl`; nothing is ever written.
///
/// Each audit log is read incrementally from the last offset, keeping a line
/// still being written as a trailing fragment. A file that shrank or was
/// replaced (new inode) is read again from the start. Only sessions that pass
/// `CoworkSessionPolicy.isTrackable` and `shouldSurfaceOnLaunch` are followed;
/// once followed, a session keeps its card until it is archived, hidden or
/// deleted (the app's own idle sweep retires quiet cards).
///
/// Not thread-safe: drive it from one serial queue.
public final class CoworkStoreScanner {
    public let root: String
    private let fileManager: FileManager
    private let freshness: TimeInterval
    /// History read on first sight is capped so one huge log cannot stall a
    /// scan; the state is then folded from the newest part only.
    private let maxInitialReadBytes: UInt64

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private struct Tracked {
        var accountDirectory: String
        var metadata: CoworkSessionMetadata
        var metadataModifiedAt: Date?
        var auditIdentity: FileIdentity?
        var offset: UInt64 = 0
        var fragment = Data()
        var state = CoworkAuditState()
        var lastSent: CoworkSessionUpdate?
    }

    private var tracked: [String: Tracked] = [:]
    /// First scan. A session created after it is news from its first line on;
    /// one that already existed is history until its log grows.
    private var startedAt: Date?
    /// Metadata seen but not (yet) worth a card, so an unchanged file is not
    /// re-parsed every scan.
    private var untracked: [String: (modifiedAt: Date?, metadata: CoworkSessionMetadata?)] = [:]

    public init(
        root: String,
        fileManager: FileManager = .default,
        freshness: TimeInterval = CoworkSessionPolicy.launchFreshness,
        maxInitialReadBytes: UInt64 = 8 * 1024 * 1024
    ) {
        self.root = root.hasSuffix("/") ? String(root.dropLast()) : root
        self.fileManager = fileManager
        self.freshness = freshness
        self.maxInitialReadBytes = maxInitialReadBytes
    }

    /// Session ids currently followed.
    public var trackedSessionIds: Set<String> { Set(tracked.keys) }

    /// One pass over the store. Returns only sessions whose update changed.
    public func scan(now: Date = Date()) -> [CoworkSessionUpdate] {
        var updates: [CoworkSessionUpdate] = []
        var seen: Set<String> = []
        let startedAt = self.startedAt ?? now
        self.startedAt = startedAt

        for (accountDirectory, sessionId) in metadataFiles() {
            seen.insert(sessionId)
            let metadataPath = CoworkPaths.metadataPath(accountDirectory: accountDirectory, sessionId: sessionId)
            let metadataModifiedAt = modificationDate(metadataPath)

            if var session = tracked[sessionId] {
                if session.metadataModifiedAt != metadataModifiedAt,
                   let data = fileManager.contents(atPath: metadataPath),
                   let metadata = CoworkSessionMetadata.parse(data) {
                    session.metadata = metadata
                    session.metadataModifiedAt = metadataModifiedAt
                }
                guard CoworkSessionPolicy.isTrackable(session.metadata) else {
                    tracked.removeValue(forKey: sessionId)
                    untracked[sessionId] = (modifiedAt: metadataModifiedAt, metadata: session.metadata)
                    updates.append(.removal(sessionId: sessionId))
                    continue
                }
                if let update = advance(&session, replaysHistory: false) { updates.append(update) }
                tracked[sessionId] = session
                continue
            }

            let metadata: CoworkSessionMetadata?
            if let cached = untracked[sessionId], cached.modifiedAt == metadataModifiedAt {
                metadata = cached.metadata
            } else {
                metadata = fileManager.contents(atPath: metadataPath).flatMap(CoworkSessionMetadata.parse)
                untracked[sessionId] = (modifiedAt: metadataModifiedAt, metadata: metadata)
            }
            guard let metadata, metadata.sessionId == sessionId, CoworkSessionPolicy.isTrackable(metadata) else { continue }
            let auditPath = CoworkPaths.auditPath(accountDirectory: accountDirectory, sessionId: sessionId)
            let audit = fileStat(auditPath)
            let lastActivity = CoworkSessionPolicy.lastActivity(metadata: metadata, auditModifiedAt: audit?.modifiedAt)
            guard CoworkSessionPolicy.shouldSurfaceOnLaunch(
                metadata: metadata, auditSize: audit?.size ?? 0, lastActivity: lastActivity,
                now: now, freshness: freshness
            ) else { continue }

            untracked.removeValue(forKey: sessionId)
            var session = Tracked(accountDirectory: accountDirectory, metadata: metadata, metadataModifiedAt: metadataModifiedAt)
            let isNew = metadata.createdAt.map { $0 >= startedAt } ?? false
            if let update = advance(&session, replaysHistory: !isNew) { updates.append(update) }
            tracked[sessionId] = session
        }

        for sessionId in tracked.keys where !seen.contains(sessionId) {
            tracked.removeValue(forKey: sessionId)
            updates.append(.removal(sessionId: sessionId))
        }
        untracked = untracked.filter { seen.contains($0.key) }
        return updates
    }

    /// Forget everything; the next scan starts as if at launch.
    public func reset() {
        tracked.removeAll()
        untracked.removeAll()
        startedAt = nil
    }

    // MARK: - Audit log

    /// Read whatever the audit log gained and return the session's update if
    /// it differs from the last one sent.
    private func advance(_ session: inout Tracked, replaysHistory: Bool) -> CoworkSessionUpdate? {
        let auditPath = CoworkPaths.auditPath(accountDirectory: session.accountDirectory, sessionId: session.metadata.sessionId)
        let audit = fileStat(auditPath)
        var isReplay = replaysHistory
        let turnsBefore = session.state.completedTurnCount

        if let audit {
            if session.auditIdentity != audit.identity || audit.size < session.offset {
                // New, replaced or truncated: start over from byte 0.
                if session.auditIdentity != nil { isReplay = true }
                session.auditIdentity = audit.identity
                session.offset = 0
                session.fragment = Data()
                session.state = CoworkAuditState()
                if audit.size > maxInitialReadBytes {
                    // Skip to the newest part; the partial first line is dropped below.
                    session.offset = audit.size - maxInitialReadBytes
                    session.fragment = Data()
                    if let chunk = read(auditPath, from: session.offset, upTo: audit.size),
                       let newline = chunk.firstIndex(of: 0x0A) {
                        session.offset += UInt64(chunk.distance(from: chunk.startIndex, to: newline) + 1)
                    }
                }
            }
            if audit.size > session.offset, let chunk = read(auditPath, from: session.offset, upTo: audit.size) {
                session.offset += UInt64(chunk.count)
                let parsed = CoworkAuditParser.events(in: session.fragment + chunk)
                session.fragment = parsed.trailingFragment
                session.state.apply(parsed.events)
            }
        } else if session.auditIdentity != nil {
            // The log disappeared; whatever replaces it is a fresh history.
            session.auditIdentity = nil
            session.offset = 0
            session.fragment = Data()
            session.state = CoworkAuditState()
        }

        let state = session.state
        let lastActivity = CoworkSessionPolicy.lastActivity(metadata: session.metadata, auditModifiedAt: audit?.modifiedAt)
            ?? session.metadata.createdAt ?? Date(timeIntervalSince1970: 0)
        let phase: CoworkSessionUpdate.Phase
        switch state.phase {
        case .idle: phase = .idle
        case .processing: phase = .processing
        case .waitingApproval: phase = .waitingApproval
        case .waitingQuestion: phase = .waitingQuestion
        }
        let active = state.activePermission
        var update = CoworkSessionUpdate(
            sessionId: session.metadata.sessionId,
            title: session.metadata.displayTitle,
            cwd: session.metadata.hostCwd,
            phase: phase,
            currentTool: active?.toolName ?? state.currentTool?.name,
            toolDetail: active.map(\.detail) ?? state.currentTool?.detail,
            lastPrompt: state.lastPrompt,
            lastResultText: state.lastResultText,
            lastActivity: lastActivity,
            cliSessionId: session.metadata.cliSessionId,
            completedTurnCount: state.completedTurnCount,
            lastTurnInterrupted: state.lastTurnInterrupted,
            lastTurnFailed: state.lastTurnFailed
        )
        update.turnEnded = !isReplay && state.completedTurnCount > turnsBefore && phase == .idle

        var comparable = update
        comparable.turnEnded = false
        guard comparable != session.lastSent || update.turnEnded else { return nil }
        session.lastSent = comparable
        return update
    }

    // MARK: - Filesystem

    /// `(accountDirectory, sessionId)` for every `<root>/<a>/<b>/local_<id>.json`.
    private func metadataFiles() -> [(String, String)] {
        var result: [(String, String)] = []
        for account in directories(in: root) where account != "skills-plugin" {
            let accountPath = root + "/" + account
            for org in directories(in: accountPath) {
                let orgPath = accountPath + "/" + org
                guard let names = try? fileManager.contentsOfDirectory(atPath: orgPath) else { continue }
                for name in names where name.hasPrefix(CoworkPaths.sessionIdPrefix) && name.hasSuffix(".json") {
                    let path = orgPath + "/" + name
                    guard let classified = CoworkPaths.classify(path: path, root: root),
                          classified.kind == .metadata else { continue }
                    result.append((classified.accountDirectory, classified.sessionId))
                }
            }
        }
        return result.sorted { $0.1 < $1.1 }
    }

    private func directories(in path: String) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: path + "/" + name, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private func modificationDate(_ path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func fileStat(_ path: String) -> (identity: FileIdentity, size: UInt64, modifiedAt: Date)? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return (FileIdentity(device: info.st_dev, inode: info.st_ino), UInt64(info.st_size), modified)
    }

    private func read(_ path: String, from offset: UInt64, upTo end: UInt64) -> Data? {
        guard end > offset, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: Int(end - offset))
        } catch {
            return nil
        }
    }
}
