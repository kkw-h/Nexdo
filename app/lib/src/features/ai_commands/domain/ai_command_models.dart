class AiCommandClassification {
  const AiCommandClassification({
    required this.intent,
    required this.operationType,
    required this.confidence,
    required this.summary,
    required this.missingSlots,
    required this.entities,
    required this.nextStep,
    required this.clarificationQuestion,
  });

  factory AiCommandClassification.fromMap(Map<String, dynamic> map) {
    return AiCommandClassification(
      intent: map['intent'] as String? ?? '',
      operationType: map['operationType'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      summary: map['summary'] as String? ?? '',
      missingSlots: ((map['missingSlots'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      entities: (map['entities'] as Map<String, dynamic>?) ?? const {},
      nextStep: map['nextStep'] as String? ?? '',
      clarificationQuestion: map['clarificationQuestion'] as String?,
    );
  }

  final String intent;
  final String operationType;
  final double confidence;
  final String summary;
  final List<String> missingSlots;
  final Map<String, dynamic> entities;
  final String nextStep;
  final String? clarificationQuestion;
}

class AiCommandContextSummary {
  const AiCommandContextSummary({
    required this.remindersLoaded,
    required this.quickNotesLoaded,
    required this.listsLoaded,
    required this.groupsLoaded,
    required this.tagsLoaded,
  });

  factory AiCommandContextSummary.fromMap(Map<String, dynamic> map) {
    return AiCommandContextSummary(
      remindersLoaded: (map['reminders_loaded'] as num?)?.toInt() ?? 0,
      quickNotesLoaded: (map['quick_notes_loaded'] as num?)?.toInt() ?? 0,
      listsLoaded: (map['lists_loaded'] as num?)?.toInt() ?? 0,
      groupsLoaded: (map['groups_loaded'] as num?)?.toInt() ?? 0,
      tagsLoaded: (map['tags_loaded'] as num?)?.toInt() ?? 0,
    );
  }

  final int remindersLoaded;
  final int quickNotesLoaded;
  final int listsLoaded;
  final int groupsLoaded;
  final int tagsLoaded;
}

class AiCommandCandidate {
  const AiCommandCandidate({
    required this.id,
    required this.title,
    required this.reason,
  });

  factory AiCommandCandidate.fromMap(Map<String, dynamic> map) {
    return AiCommandCandidate(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final String reason;
}

class AiCommandProposal {
  const AiCommandProposal({
    required this.action,
    required this.targetType,
    required this.targetIds,
    required this.patch,
    required this.reason,
    required this.riskLevel,
  });

  factory AiCommandProposal.fromMap(Map<String, dynamic> map) {
    return AiCommandProposal(
      action: map['action'] as String? ?? '',
      targetType: map['targetType'] as String? ?? '',
      targetIds: ((map['targetIds'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      patch: (map['patch'] as Map<String, dynamic>?) ?? const {},
      reason: map['reason'] as String? ?? '',
      riskLevel: map['riskLevel'] as String? ?? '',
    );
  }

  final String action;
  final String targetType;
  final List<String> targetIds;
  final Map<String, dynamic> patch;
  final String reason;
  final String riskLevel;
}

class AiCommandPlanStep {
  const AiCommandPlanStep({
    required this.step,
    required this.summary,
    required this.action,
    required this.targetType,
    required this.targetIds,
    required this.patch,
    required this.reason,
    required this.riskLevel,
    List<AiCommandPreviewItem>? previewItems,
  }) : _previewItems = previewItems;

  factory AiCommandPlanStep.fromMap(Map<String, dynamic> map) {
    return AiCommandPlanStep(
      step: (map['step'] as num?)?.toInt() ?? 0,
      summary: map['summary'] as String? ?? '',
      action: map['action'] as String? ?? '',
      targetType: map['targetType'] as String? ?? '',
      targetIds: ((map['targetIds'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      patch: (map['patch'] as Map<String, dynamic>?) ?? const {},
      reason: map['reason'] as String? ?? '',
      riskLevel: map['riskLevel'] as String? ?? '',
      previewItems: ((map['previewItems'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiCommandPreviewItem.fromMap)
          .toList(),
    );
  }

  final int step;
  final String summary;
  final String action;
  final String targetType;
  final List<String> targetIds;
  final Map<String, dynamic> patch;
  final String reason;
  final String riskLevel;
  final List<AiCommandPreviewItem>? _previewItems;

  List<AiCommandPreviewItem> get previewItems => _previewItems ?? const [];
}

class AiCommandPreviewItem {
  const AiCommandPreviewItem({
    required this.targetId,
    required this.title,
    required this.action,
    required this.before,
    required this.after,
  });

  factory AiCommandPreviewItem.fromMap(Map<String, dynamic> map) {
    return AiCommandPreviewItem(
      targetId: map['targetId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      action: map['action'] as String? ?? '',
      before: ((map['before'] as Map?) ?? const <dynamic, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
      after: ((map['after'] as Map?) ?? const <dynamic, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
    );
  }

  final String targetId;
  final String title;
  final String action;
  final Map<String, String> before;
  final Map<String, String> after;
}

class AiCommandResult {
  const AiCommandResult({
    required this.status,
    required this.intent,
    required this.operationType,
    required this.requiresConfirmation,
    required this.summary,
    required this.userMessage,
    required this.missingSlots,
    required this.answer,
    required this.clarificationQuestion,
    required this.confirmationMessage,
    required this.proposal,
    required this.plan,
    required this.candidates,
  });

  factory AiCommandResult.fromMap(Map<String, dynamic> map) {
    return AiCommandResult(
      status: map['status'] as String? ?? '',
      intent: map['intent'] as String? ?? '',
      operationType: map['operationType'] as String? ?? '',
      requiresConfirmation: map['requiresConfirmation'] as bool? ?? false,
      summary: map['summary'] as String? ?? '',
      userMessage: map['userMessage'] as String? ?? '',
      missingSlots: ((map['missingSlots'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      answer: map['answer'] as String?,
      clarificationQuestion: map['clarificationQuestion'] as String?,
      confirmationMessage: map['confirmationMessage'] as String?,
      proposal: map['proposal'] is Map<String, dynamic>
          ? AiCommandProposal.fromMap(map['proposal'] as Map<String, dynamic>)
          : null,
      plan: ((map['plan'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiCommandPlanStep.fromMap)
          .toList(),
      candidates: ((map['candidates'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiCommandCandidate.fromMap)
          .toList(),
    );
  }

  final String status;
  final String intent;
  final String operationType;
  final bool requiresConfirmation;
  final String summary;
  final String userMessage;
  final List<String> missingSlots;
  final String? answer;
  final String? clarificationQuestion;
  final String? confirmationMessage;
  final AiCommandProposal? proposal;
  final List<AiCommandPlanStep> plan;
  final List<AiCommandCandidate> candidates;
}

class AiCommandConfirmation {
  const AiCommandConfirmation({required this.token, required this.expiresAt});

  factory AiCommandConfirmation.fromMap(Map<String, dynamic> map) {
    return AiCommandConfirmation(
      token: map['token'] as String? ?? '',
      expiresAt: map['expires_at'] as String? ?? '',
    );
  }

  final String token;
  final String expiresAt;
}

class AiCommandResolveResponse {
  const AiCommandResolveResponse({
    required this.input,
    required this.mode,
    required this.classification,
    required this.contextSummary,
    required this.result,
    required this.confirmation,
  });

  factory AiCommandResolveResponse.fromMap(Map<String, dynamic> map) {
    return AiCommandResolveResponse(
      input: map['input'] as String? ?? '',
      mode: map['mode'] as String? ?? '',
      classification: AiCommandClassification.fromMap(
        (map['classification'] as Map<String, dynamic>?) ?? const {},
      ),
      contextSummary: AiCommandContextSummary.fromMap(
        (map['context_summary'] as Map<String, dynamic>?) ?? const {},
      ),
      result: AiCommandResult.fromMap(
        (map['result'] as Map<String, dynamic>?) ?? const {},
      ),
      confirmation: map['confirmation'] is Map<String, dynamic>
          ? AiCommandConfirmation.fromMap(
              map['confirmation'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  final String input;
  final String mode;
  final AiCommandClassification classification;
  final AiCommandContextSummary contextSummary;
  final AiCommandResult result;
  final AiCommandConfirmation? confirmation;
}

class AiCommandClaims {
  const AiCommandClaims({
    required this.userId,
    required this.intent,
    required this.operationType,
    required this.action,
    required this.targetType,
    required this.targetIds,
    required this.proposalHash,
    required this.stepCount,
  });

  factory AiCommandClaims.fromMap(Map<String, dynamic> map) {
    return AiCommandClaims(
      userId: map['user_id'] as String? ?? '',
      intent: map['intent'] as String? ?? '',
      operationType: map['operation_type'] as String? ?? '',
      action: map['action'] as String? ?? '',
      targetType: map['target_type'] as String? ?? '',
      targetIds: ((map['target_ids'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      proposalHash: map['proposal_hash'] as String? ?? '',
      stepCount: (map['step_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String userId;
  final String intent;
  final String operationType;
  final String action;
  final String targetType;
  final List<String> targetIds;
  final String proposalHash;
  final int stepCount;
}

class AiCommandVerifyResponse {
  const AiCommandVerifyResponse({
    required this.valid,
    required this.expiresAt,
    required this.claims,
  });

  factory AiCommandVerifyResponse.fromMap(Map<String, dynamic> map) {
    return AiCommandVerifyResponse(
      valid: map['valid'] as bool? ?? false,
      expiresAt: map['expires_at'] as String? ?? '',
      claims: AiCommandClaims.fromMap(
        (map['claims'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final bool valid;
  final String expiresAt;
  final AiCommandClaims claims;
}

class AiCommandExecuteResponse {
  const AiCommandExecuteResponse({
    required this.executed,
    required this.action,
    required this.result,
    required this.claims,
  });

  factory AiCommandExecuteResponse.fromMap(Map<String, dynamic> map) {
    return AiCommandExecuteResponse(
      executed: map['executed'] as bool? ?? false,
      action: map['action'] as String? ?? '',
      result: (map['result'] as List<dynamic>?) ?? const [],
      claims: AiCommandClaims.fromMap(
        (map['claims'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final bool executed;
  final String action;
  final List<dynamic> result;
  final AiCommandClaims claims;

  int get affectedItemCount => _countExecutionItems(result);

  List<String> get resultSummaryLines => _summarizeExecutionItems(result);
}

int _countExecutionItems(dynamic value) {
  if (value is List<dynamic>) {
    return value.fold<int>(0, (sum, item) => sum + _countExecutionItems(item));
  }
  if (value is Map<String, dynamic>) {
    final reminderIDs = value['reminder_ids'];
    if (reminderIDs is List<dynamic>) {
      return reminderIDs.length;
    }
    if (value.containsKey('id')) {
      return 1;
    }
    if (value['deleted'] == true) {
      return 1;
    }
  }
  return value == null ? 0 : 1;
}

List<String> _summarizeExecutionItems(dynamic value) {
  if (value is List<dynamic>) {
    return value
        .expand<String>(_summarizeExecutionItems)
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }
  if (value is Map<String, dynamic>) {
    final title = value['title']?.toString();
    if (title != null && title.trim().isNotEmpty) {
      return <String>[title.trim()];
    }
    final reminderIDs = value['reminder_ids'];
    if (reminderIDs is List<dynamic> && reminderIDs.isNotEmpty) {
      return <String>['已删除 ${reminderIDs.length} 条提醒'];
    }
    final action = value['action']?.toString();
    if (action != null && action.trim().isNotEmpty) {
      return <String>[action.trim()];
    }
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const <String>[] : <String>[text];
}

class AiCommandStreamEvent {
  const AiCommandStreamEvent({
    required this.event,
    this.stage,
    this.message,
    this.code,
    this.detail,
    this.resolved,
  });

  factory AiCommandStreamEvent.fromMap(Map<String, dynamic> map) {
    final event = map['event'] as String? ?? 'message';
    final data = map['data'];
    if (event == 'result' && data is Map<String, dynamic>) {
      return AiCommandStreamEvent(
        event: event,
        resolved: AiCommandResolveResponse.fromMap(data),
      );
    }
    if (data is Map<String, dynamic>) {
      return AiCommandStreamEvent(
        event: event,
        stage: data['stage'] as String?,
        message: data['message'] as String?,
        code: (data['code'] as num?)?.toInt(),
        detail: data['detail'] as String?,
      );
    }
    return AiCommandStreamEvent(event: event, message: data?.toString());
  }

  final String event;
  final String? stage;
  final String? message;
  final int? code;
  final String? detail;
  final AiCommandResolveResponse? resolved;
}
