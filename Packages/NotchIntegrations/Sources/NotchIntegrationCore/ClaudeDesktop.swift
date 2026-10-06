import Foundation
import CodeIslandCore

/// Sessions that live in the Claude desktop app: Cowork tasks, read from its
/// session store, and Code-tab conversations, which arrive through hooks.
public enum ClaudeDesktop {
    public static let bundleId = "com.anthropic.claudefordesktop"
    public static let displayName = "Claude 桌面版"

    /// A Cowork card is keyed by Claude Desktop's own `local_<id>`.
    public static func isCoworkSession(id: String) -> Bool {
        CoworkPaths.isValidSessionId(id)
    }

    public static func isDesktopSession(_ snapshot: SessionSnapshot) -> Bool {
        snapshot.termBundleId == bundleId
    }

    /// Card label naming where the session runs, nil for everything else.
    public static func hostLabel(id: String, snapshot: SessionSnapshot) -> String? {
        guard isDesktopSession(snapshot) else { return nil }
        return isCoworkSession(id: id) ? displayName + " · Cowork" : displayName
    }

    /// What a click opens: the Cowork screen of that task, nil otherwise.
    public static func deepLink(id: String, snapshot: SessionSnapshot) -> URL? {
        guard isDesktopSession(snapshot), isCoworkSession(id: id) else { return nil }
        return CoworkSessionPolicy.deepLinkURL(sessionId: id)
    }

    public enum CoworkOutcome: Equatable, Sendable {
        /// The card was created or refreshed. `turnEnded` when a turn just
        /// finished normally and the conversation should be revealed.
        case updated(turnEnded: Bool)
        /// Archived, hidden or deleted in Claude Desktop: the card is gone.
        case removed
        /// A hook-driven card already shows this conversation; it wins.
        case shadowed
        case ignored
    }

    /// Fold one helper update into the session list.
    ///
    /// Waiting phases only set the status: the island cannot answer Claude
    /// Desktop's permission cards, so nothing is queued and the card points
    /// the user back to the app (see `DisplayOnlyWait`).
    @discardableResult
    public static func apply(_ update: CoworkSessionUpdate, to sessions: inout [String: SessionSnapshot]) -> CoworkOutcome {
        let id = update.sessionId
        guard isCoworkSession(id: id) else { return .ignored }
        if update.removed {
            return sessions.removeValue(forKey: id) == nil ? .ignored : .removed
        }
        var otherKeys = Set(sessions.keys)
        otherKeys.remove(id)
        if CoworkSessionPolicy.isShadowedByHookSession(cliSessionId: update.cliSessionId, existingSessionKeys: otherKeys) {
            sessions.removeValue(forKey: id)
            return .shadowed
        }

        var snapshot = sessions[id] ?? SessionSnapshot(startTime: update.lastActivity)
        snapshot.source = "claude"
        snapshot.termBundleId = bundleId
        snapshot.providerSessionId = update.cliSessionId
        snapshot.sessionTitle = update.title
        snapshot.cwd = update.cwd
        switch update.phase {
        case .idle: snapshot.status = .idle
        case .processing: snapshot.status = .processing
        case .waitingApproval: snapshot.status = .waitingApproval
        case .waitingQuestion: snapshot.status = .waitingQuestion
        }
        if update.phase == .idle {
            snapshot.currentTool = nil
            snapshot.toolDescription = nil
        } else {
            snapshot.currentTool = update.currentTool
            snapshot.toolDescription = update.toolDetail
        }
        snapshot.lastUserPrompt = update.lastPrompt
        if let result = update.lastResultText { snapshot.lastAssistantMessage = result }
        else if update.phase != .idle { snapshot.lastAssistantMessage = nil }
        snapshot.lastActivity = update.lastActivity
        snapshot.interrupted = update.phase == .idle && update.lastTurnInterrupted
        sessions[id] = snapshot
        return .updated(turnEnded: update.turnEnded && update.phase == .idle && !update.lastTurnInterrupted)
    }
}
