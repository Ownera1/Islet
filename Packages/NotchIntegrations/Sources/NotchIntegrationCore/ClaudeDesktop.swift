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

    // MARK: Subscription

    /// Claude Desktop's login is encrypted with its own "Claude Safe Storage"
    /// key and is never read here, and refreshing tokens on its behalf would
    /// log the CLI out. So without a Claude Code login there is no quota.
    public static let noReadableQuotaMessage = "Claude 桌面版不提供可读取的额度。在终端运行一次 `claude` 登录后，Islet 可显示实时额度。"

    /// Text for "no Claude Code login": points desktop-only users at the CLI.
    public static func missingLoginMessage(home: String, fileManager: FileManager = .default) -> String {
        var isDirectory: ObjCBool = false
        let hasDesktop = fileManager.fileExists(atPath: CoworkPaths.claudeSupportDirectory(home: home), isDirectory: &isDirectory)
            && isDirectory.boolValue
        return hasDesktop ? noReadableQuotaMessage : "请先登录 Claude Code。"
    }

    // MARK: Code tab (hooks)

    /// Who answers a `PermissionRequest` hook.
    public enum PermissionHandling: Equatable, Sendable {
        /// Held until the user decides in the notch (terminal sessions).
        case island
        /// Answered `{}` at once, so the host shows its own card; the notch
        /// only mirrors the wait and offers to jump there.
        case displayOnly
    }

    /// Code-tab sessions are answered in the notch like terminal sessions.
    /// Measured (docs/claude-desktop-support.md, step 0.2): Claude Desktop
    /// applies the hook's allow / deny, but also shows its own card while the
    /// hook is held. A decision made there does not end the hook, so the
    /// island drops its copy when the tool finishes (`isAnsweredInApp`).
    /// `.displayOnly` answers `{}` at once and leaves the decision to the app.
    public static let codeTabPermissionHandling: PermissionHandling = .island

    /// Whether a finished tool (`PostToolUse` / `PostToolUseFailure`) is the
    /// one a held Code-tab request guards, i.e. it was decided in Claude
    /// Desktop's own card. Same tool and same input; a parallel tool that
    /// finishes meanwhile leaves the request alone.
    public static func isAnsweredInApp(requestTool: String, requestInput: [String: Any],
                                       finishedTool: String?, finishedInput: [String: Any]?) -> Bool {
        guard let finishedTool, finishedTool == requestTool else { return false }
        return NSDictionary(dictionary: requestInput).isEqual(to: finishedInput ?? [:])
    }

    /// `termBundle` is the hook's `_term_bundle` (the host app's
    /// `__CFBundleIdentifier`, inherited by hook subprocesses).
    public static func permissionHandling(termBundle: String?) -> PermissionHandling {
        termBundle == bundleId ? codeTabPermissionHandling : .island
    }

    // MARK: Cowork (session store)

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
