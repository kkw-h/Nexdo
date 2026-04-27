package app

type aiCommandResolveRequest struct {
	Input string `json:"input"`
}

type aiCommandStreamStatusPayload struct {
	Stage   string `json:"stage"`
	Message string `json:"message"`
}

type aiCommandStreamErrorPayload struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Detail  string `json:"detail,omitempty"`
}

type aiCommandClassifyRequest struct {
	UserInput string `json:"userInput"`
	Timezone  string `json:"timezone"`
	Now       string `json:"now,omitempty"`
}

type aiCommandClassifyResponse struct {
	OK             bool                          `json:"ok"`
	Classification aiCommandClassificationResult `json:"classification"`
}

type aiCommandClassificationResult struct {
	Intent                string         `json:"intent"`
	OperationType         string         `json:"operationType"`
	Confidence            float64        `json:"confidence"`
	Summary               string         `json:"summary"`
	MissingSlots          []string       `json:"missingSlots"`
	Entities              map[string]any `json:"entities"`
	NextStep              string         `json:"nextStep"`
	ClarificationQuestion *string        `json:"clarificationQuestion"`
}

type aiCommandReminderCandidate struct {
	ID        string   `json:"id"`
	Title     string   `json:"title"`
	DueAt     *string  `json:"dueAt,omitempty"`
	Note      *string  `json:"note,omitempty"`
	Completed bool     `json:"completed"`
	ListName  *string  `json:"listName,omitempty"`
	GroupName *string  `json:"groupName,omitempty"`
	Tags      []string `json:"tags,omitempty"`
	Aliases   []string `json:"aliases,omitempty"`
}

type aiCommandQuickNoteCandidate struct {
	ID        string  `json:"id"`
	Content   string  `json:"content"`
	CreatedAt *string `json:"createdAt,omitempty"`
}

type aiCommandResourceCandidate struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type aiCommandContextPayload struct {
	Reminders  []aiCommandReminderCandidate  `json:"reminders"`
	QuickNotes []aiCommandQuickNoteCandidate `json:"quickNotes"`
	Lists      []aiCommandResourceCandidate  `json:"lists"`
	Groups     []aiCommandResourceCandidate  `json:"groups"`
	Tags       []aiCommandResourceCandidate  `json:"tags"`
}

type aiCommandProposeRequest struct {
	UserInput      string                        `json:"userInput"`
	Classification aiCommandClassificationResult `json:"classification"`
	Timezone       string                        `json:"timezone"`
	Now            string                        `json:"now,omitempty"`
	Context        aiCommandContextPayload       `json:"context"`
}

type aiCommandCandidateSummary struct {
	ID     string `json:"id"`
	Title  string `json:"title"`
	Reason string `json:"reason"`
}

type aiCommandProposalPayload struct {
	Action     string         `json:"action"`
	TargetType string         `json:"targetType"`
	TargetIDs  []string       `json:"targetIds"`
	Patch      map[string]any `json:"patch"`
	Reason     string         `json:"reason"`
	RiskLevel  string         `json:"riskLevel"`
}

type aiCommandPlanStep struct {
	Step         int                    `json:"step"`
	Summary      string                 `json:"summary"`
	Action       string                 `json:"action"`
	TargetType   string                 `json:"targetType"`
	TargetIDs    []string               `json:"targetIds"`
	Patch        map[string]any         `json:"patch"`
	Reason       string                 `json:"reason"`
	RiskLevel    string                 `json:"riskLevel"`
	PreviewItems []aiCommandPreviewItem `json:"previewItems,omitempty"`
}

type aiCommandPreviewItem struct {
	TargetID string            `json:"targetId"`
	Title    string            `json:"title"`
	Action   string            `json:"action"`
	Before   map[string]string `json:"before,omitempty"`
	After    map[string]string `json:"after,omitempty"`
}

type aiCommandProposalResult struct {
	Status                string                      `json:"status"`
	Intent                string                      `json:"intent"`
	OperationType         string                      `json:"operationType"`
	RequiresConfirmation  bool                        `json:"requiresConfirmation"`
	Summary               string                      `json:"summary"`
	UserMessage           string                      `json:"userMessage"`
	MissingSlots          []string                    `json:"missingSlots"`
	Answer                *string                     `json:"answer"`
	ClarificationQuestion *string                     `json:"clarificationQuestion"`
	ConfirmationMessage   *string                     `json:"confirmationMessage"`
	Proposal              *aiCommandProposalPayload   `json:"proposal"`
	Plan                  []aiCommandPlanStep         `json:"plan"`
	Candidates            []aiCommandCandidateSummary `json:"candidates"`
}

type aiCommandProposeResponse struct {
	OK       bool                    `json:"ok"`
	Proposal aiCommandProposalResult `json:"proposal"`
}

type aiCommandResolveResponse struct {
	Input          string                        `json:"input"`
	Mode           string                        `json:"mode"`
	Classification aiCommandClassificationResult `json:"classification"`
	ContextSummary aiCommandContextSummary       `json:"context_summary"`
	Result         aiCommandProposalResult       `json:"result"`
	Confirmation   *aiCommandConfirmationPayload `json:"confirmation,omitempty"`
}

type aiCommandContextSummary struct {
	RemindersLoaded  int `json:"reminders_loaded"`
	QuickNotesLoaded int `json:"quick_notes_loaded"`
	ListsLoaded      int `json:"lists_loaded"`
	GroupsLoaded     int `json:"groups_loaded"`
	TagsLoaded       int `json:"tags_loaded"`
}

type aiCommandConfirmationPayload struct {
	Token     string `json:"token"`
	ExpiresAt string `json:"expires_at"`
}

type aiCommandVerifyRequest struct {
	Token string `json:"token"`
}

type aiCommandExecuteRequest struct {
	Token string `json:"token"`
}

type aiCommandVerifyResponse struct {
	Valid     bool                            `json:"valid"`
	ExpiresAt string                          `json:"expires_at"`
	Claims    aiCommandConfirmationClaimsView `json:"claims"`
}

type aiCommandConfirmationClaimsView struct {
	UserID        string   `json:"user_id"`
	Intent        string   `json:"intent"`
	OperationType string   `json:"operation_type"`
	Action        string   `json:"action"`
	TargetType    string   `json:"target_type"`
	TargetIDs     []string `json:"target_ids"`
	ProposalHash  string   `json:"proposal_hash"`
	StepCount     int      `json:"step_count"`
}

type aiCommandExecuteResponse struct {
	Executed bool                            `json:"executed"`
	Action   string                          `json:"action"`
	Result   []any                           `json:"result"`
	Claims   aiCommandConfirmationClaimsView `json:"claims"`
}
