import AppKit

class TerminalView: NSView {
    enum TranscriptReplayRestoreStrategy {
        case preserveVisiblePosition
        case focusUnreadBoundary(lastReadHistoryCount: Int)
    }

    let scrollView = NSScrollView()
    let transcriptContainer = FlippedView()
    let transcriptStack = NSStackView()
    let inputField = NSTextField()
    let liveStatusContainer = NSView()
    let liveStatusSpinner = NSProgressIndicator()
    let liveStatusAvatarView = NSImageView()
    let liveStatusLabel = NSTextField(labelWithString: "")
    let attachmentStrip = NSView()
    let attachmentScrollView = NSScrollView()
    let attachmentPreviewDocumentView = NSView()
    let attachmentPreviewStack = NSStackView()
    let attachmentHintLabel = NSTextField(labelWithString: "")
    let expertSuggestionContainer = NSView()
    let expertSuggestionLabel = NSTextField(labelWithString: "")
    let expertSuggestionStack = NSStackView()
    let attachButton = HoverButton(title: "", target: nil, action: nil)
    let dictateButton = HoverButton(title: "", target: nil, action: nil)
    let sendButton = HoverButton(title: "", target: nil, action: nil)
    /// Owned by the terminal so the manager survives the duration of
    /// the popover lifetime. Lazy so the audio/speech frameworks aren't
    /// touched until the user clicks dictate for the first time.
    lazy var dictationManager = DictationManager()
    /// Snapshot of `inputField.stringValue` at the moment dictation
    /// started. Live partial transcripts are appended to this prefix
    /// so the user's pre-existing typed text isn't overwritten.
    var dictationBaselineText: String = ""
    var isDictating: Bool = false
    let composerStatusLabel = NSTextField(labelWithString: "Generating...")
    let returnButton = NSButton(title: "Back to Orion", target: nil, action: nil)
    var onSendMessage: ((String, [SessionAttachment]) -> Void)?
    var onStopRequested: (() -> Void)?
    var onReturnToLenny: (() -> Void)?
    var onSelectExpert: ((ResponderExpert) -> Void)?
    var onSelectExpertSuggestion: ((UUID, ResponderExpert) -> Void)?
    var onEditExpertSuggestion: ((UUID) -> Void)?
    var onTogglePinned: (() -> Void)?
    var onCloseRequested: (() -> Void)?
    var onRefreshSetupState: (() -> Void)?
    var onApprovalResponse: ((ClaudeSession.ApprovalChoice) -> Void)?
    var onReachedTranscriptBottom: (() -> Void)?

    var characterColor: NSColor?
    var themeOverride: PopoverTheme?
    var currentAssistantText = ""
    var isStreaming = false
    var placeholderText = "Ask a question or drop in a file"
    var welcomeChipsView: WelcomeChipsView?
    var pendingAttachments: [SessionAttachment] = []
    var expertSuggestionTargets: [String: ResponderExpert] = [:]
    var deferredExpertSuggestions: [ResponderExpert] = []
    var currentExpertSuggestions: [ResponderExpert] = []
    var lastPickedExpert: ResponderExpert?
    var isShowingInitialWelcomeState = false
    var transcriptSuggestionView: NSView?
    /// Tappable chip pair showing 2 LLM-generated follow-up prompts after
    /// each substantive assistant response. Lives at the bottom of the
    /// transcript stack, cleared when the user types or sends or when
    /// the next response begins streaming. Owned by TerminalView so the
    /// transcript replay path doesn't accidentally double-render.
    var followUpChipsView: FollowUpChipsView?
    var transcriptLiveStatusView: NSView?
    var transcriptApprovalView: NSView?
    var renderedConversationKey: String?
    var expertSuggestionsCollapsed = false
    var liveStatusAvatarTimer: Timer?
    var liveStatusAvatarPaths: [String] = []
    var liveStatusAvatarIndex = 0
    var streamingPresentationInterrupted = false
    var currentStreamingSpeakerName: String?
    var isPinnedOpen = false
    var isShowingDropTarget = false
    var isExpertMode = false
    var isReplayingTranscript = false
    var starterPackWelcomeBannerDismissed = false
    /// Session-only flag: set when the user explicitly dismisses the proactive
    /// MCP setup banner. Resets on the next app open so they get a reminder.
    var mcpSetupBannerDismissedThisSession = false
    /// Session-only flag: set when the user clicks "Skip for now" on the
    /// business-context survey card. Persistent dismissal lives in
    /// `AppSettings.markBusinessContextPromptShown()` (stamps the current
    /// app version). This flag avoids re-rendering the card after skip
    /// within the same session, even though the persistent stamp also
    /// suppresses it.
    var businessContextPromptDismissedThisSession = false
    var currentWelcomeSuggestions: [(String, String, String)] = []
    var lastRenderedWelcomeSignature: String?
    var isShowingOfficialMCPSetupPanel = false
    var requiresInitialConnectionSetup = false
    var lastObservedFirstRunConfigurationSignature: String?
    var settingsObserver: NSObjectProtocol?
    let officialMCPURL = URL(string: "https://yourorbit.team")!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    deinit {
        liveStatusAvatarTimer?.invalidate()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    var theme: PopoverTheme {
        var t = themeOverride ?? PopoverTheme.current
        if let color = characterColor {
            t = t.withCharacterColor(color)
        }
        t = t.withCustomFont()
        return t
    }

    override func layout() {
        super.layout()
        relayoutPanels()
        propagateBubbleMaxWidth()
    }

    /// Tell every existing chat bubble what the maximum text-column
    /// width should be, based on the current TerminalView frame.
    ///
    /// Computed directly from `frame.width - padding*2` rather than
    /// reading `transcriptStack.bounds.width` because the stack's
    /// bounds lag the container's frame on the same layout tick (the
    /// container width is set via direct frame mutation in
    /// relayoutPanels; autolayout takes a tick to propagate that to
    /// the constrained stack). The bubble width fix in v0.1.41 read
    /// the stale stack bounds and routinely got 0, hitting the
    /// early-return guard, which is why expand stayed broken.
    ///
    /// Soft-capped at 720pt so very wide popovers don't produce
    /// hard-to-read line lengths; floored at 280 so first layout
    /// passes (frame.width near zero) don't crush bubbles.
    private func propagateBubbleMaxWidth() {
        let target = currentBubbleMaxWidth()
        for view in transcriptStack.arrangedSubviews {
            if let bubble = view as? ChatBubbleView, bubble.maxBubbleWidth != target {
                bubble.maxBubbleWidth = target
            }
        }
    }

    /// The bubble max-width Sir's bubbles SHOULD use right now.
    /// Public so `appendBubble` can apply it immediately on a
    /// freshly-constructed bubble — without that, new bubbles render
    /// at the 380pt default for one frame before the next layout
    /// pass corrects them.
    func currentBubbleMaxWidth() -> CGFloat {
        BubbleWidthMath.maxBubbleWidth(
            forFrameWidth: frame.width,
            sidePadding: Layout.padding
        )
    }

    func setReturnToLennyVisible(_ visible: Bool) {
        returnButton.isHidden = !visible
    }
}
