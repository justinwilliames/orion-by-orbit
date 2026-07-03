import Foundation

final class ClaudeSession {
    enum Constants {
        static let openAIEndpoint = URL(string: "https://api.openai.com/v1/responses")!
        static let requestTimeout: TimeInterval = 120
    }

    enum Backend: Equatable {
        case claudeCodeCLI(path: String)
        case codexCLI(path: String)
        case openAIResponsesAPI
    }

    struct ApprovalRequest: Equatable {
        let serverName: String
        let toolName: String
        var details: [String] = []
    }

    enum ApprovalChoice: String {
        case allow = "1"
        case allowForSession = "2"
        case alwaysAllow = "3"
        case cancel = "4"
    }

    var isRunning = false
    var isBusy = false
    /// True once the backend scan (claude → codex → OpenAI) has run to
    /// completion at least once, regardless of outcome. Lets the UI tell
    /// "still detecting" apart from "detected, nothing found".
    var hasResolvedBackendOnce = false
    /// The setup-required message from the most recent backend scan, or
    /// nil when a backend was successfully selected. Recorded even when no
    /// terminalView is attached yet (eager launch-time warm-up), so the
    /// popover can reflect the already-known result the moment it opens
    /// instead of flashing a stale welcome state before re-resolving.
    var lastSetupRequiredMessage: String?
    var conversations: [String: ConversationState] = [:]
    var focusedExpert: ResponderExpert?
    var selectedBackend: Backend?
    var selectedBackendPreferenceKey: String?
    var pendingExperts: [ResponderExpert] = []
    var livePresenceExperts: [ResponderExpert] = []
    var liveToolCallsByID: [String: (name: String, arguments: [String: Any])] = [:]
    var assistantExplicitlyRequestedExperts = false
    var currentProcess: Process?
    var currentProcessStdin: FileHandle?
    var currentDataTask: URLSessionDataTask?
    var currentStreamingTask: Task<Void, Never>?
    var isCancellingTurn = false
    var pendingApprovalRequest: ApprovalRequest?

    var onTextDelta: ((String) -> Void)?
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onSetupRequired: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?
    var onExpertsUpdated: (([ResponderExpert]) -> Void)?
    var onApprovalRequested: ((ApprovalRequest) -> Void)?
    var onApprovalCleared: (() -> Void)?
    var onMCPAuthFailure: (() -> Void)?

    static var shellEnvironment: [String: String]?
    static var shellEnvironmentResolvedAt: Date?
    static var openAIKey: String?

    func selectedClaudeModel() -> String? {
        let model = AppSettings.preferredClaudeModel
        return model == .default ? nil : model.rawValue
    }

    func selectedClaudeModelLabel() -> String {
        AppSettings.preferredClaudeModel.label
    }

    func selectedCodexModel() -> String? {
        let model = AppSettings.preferredCodexModel
        return model == .default ? nil : model.rawValue
    }

    func selectedCodexModelLabel() -> String {
        AppSettings.preferredCodexModel.label
    }

    func selectedOpenAIModel() -> String {
        AppSettings.preferredOpenAIModel.rawValue
    }

    func selectedOpenAIModelLabel() -> String {
        AppSettings.preferredOpenAIModel.label
    }
}
