import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_ui_primitives.dart';
import '../../auth/data/auth_repository.dart';
import '../data/ai_command_repository.dart';
import '../domain/ai_command_models.dart';

class AiCommandPage extends StatefulWidget {
  const AiCommandPage({
    super.key,
    required this.repository,
    this.onExecuted,
    this.onSessionExpired,
    this.embedded = false,
  });

  final AiCommandRepository repository;
  final Future<void> Function()? onExecuted;
  final Future<void> Function()? onSessionExpired;
  final bool embedded;

  @override
  State<AiCommandPage> createState() => _AiCommandPageState();
}

class _AiCommandPageState extends State<AiCommandPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AiChatMessage> _messages = <_AiChatMessage>[
    _AiChatMessage.assistant(text: '直接输入你要处理的提醒，我会先解析，再在需要时向你确认执行。'),
  ];

  bool _resolving = false;
  bool _executing = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _resolving || _executing) {
      return;
    }
    developer.log('[AiCommandPage] send input="$input"');
    _controller.clear();
    final pending = _AiChatMessage.status(
      label: '解析中',
      detail: '正在理解你的指令并加载上下文',
    );
    setState(() {
      _messages.add(_AiChatMessage.user(text: input));
      _messages.add(pending);
      _resolving = true;
    });
    _scrollToBottom();
    try {
      await for (final event in widget.repository.resolveStream(input)) {
        if (!mounted) {
          return;
        }
        if (event.event == 'status') {
          developer.log(
            '[AiCommandPage] stream status stage=${event.stage} message=${event.message}',
          );
          setState(() {
            pending
              ..state = _stateForStage(event.stage)
              ..label = _labelForStage(event.stage)
              ..detail = event.message ?? pending.detail;
          });
          continue;
        }
        if (event.event == 'result' && event.resolved != null) {
          final resolved = event.resolved!;
          developer.log(
            '[AiCommandPage] stream result mode=${resolved.mode} status=${resolved.result.status} requiresConfirmation=${resolved.result.requiresConfirmation}',
          );
          setState(() {
            pending
              ..state = _stateForResult(resolved.result)
              ..label = _labelForResult(resolved.result)
              ..detail = _detailForResult(resolved);
            _messages.add(_AiChatMessage.resolved(resolved));
          });
          _scrollToBottom();
        }
      }
    } on AuthException catch (error) {
      developer.log(
        '[AiCommandPage] send auth error message=${error.message} shouldLogout=${error.shouldLogout}',
      );
      await _handleAuthException(error);
      if (!mounted) {
        return;
      }
      setState(() {
        pending
          ..state = _AiMessageState.error
          ..label = '解析失败'
          ..detail = error.message;
      });
    } catch (error) {
      developer.log('[AiCommandPage] send unexpected error=$error');
      if (!mounted) {
        return;
      }
      setState(() {
        pending
          ..state = _AiMessageState.error
          ..label = '解析失败'
          ..detail = '请稍后重试';
      });
      _showMessage('解析失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
        });
      }
    }
  }

  Future<void> _execute(_AiChatMessage message) async {
    final token = message.resolved?.confirmation?.token;
    if (token == null || token.isEmpty || _executing) {
      return;
    }
    developer.log(
      '[AiCommandPage] execute tapped tokenLength=${token.length} summary=${message.resolved?.result.summary}',
    );
    setState(() {
      _executing = true;
      message
        ..state = _AiMessageState.executing
        ..label = '执行中'
        ..detail = '正在校验确认信息并执行计划';
    });
    _scrollToBottom();
    try {
      final verified = await widget.repository.verify(token);
      developer.log(
        '[AiCommandPage] verify result valid=${verified.valid} action=${verified.claims.action}',
      );
      if (!mounted) {
        return;
      }
      if (!verified.valid) {
        setState(() {
          message
            ..verified = verified
            ..state = _AiMessageState.error
            ..label = '确认已失效'
            ..detail = '请重新发送指令';
        });
        return;
      }
      final executed = await widget.repository.execute(token);
      developer.log(
        '[AiCommandPage] execute result executed=${executed.executed} action=${executed.action} items=${executed.affectedItemCount}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        message
          ..verified = verified
          ..executed = executed
          ..state = _AiMessageState.completed
          ..label = '已执行'
          ..detail = _executionSummary(executed);
      });
      if (widget.onExecuted != null) {
        await widget.onExecuted!.call();
      }
      _showMessage('AI 指令已执行');
    } on AuthException catch (error) {
      developer.log(
        '[AiCommandPage] execute auth error message=${error.message} shouldLogout=${error.shouldLogout}',
      );
      await _handleAuthException(error);
      if (!mounted) {
        return;
      }
      setState(() {
        message
          ..state = _AiMessageState.error
          ..label = '执行失败'
          ..detail = error.message;
      });
    } catch (error) {
      developer.log('[AiCommandPage] execute unexpected error=$error');
      if (!mounted) {
        return;
      }
      setState(() {
        message
          ..state = _AiMessageState.error
          ..label = '执行失败'
          ..detail = '请稍后重试';
      });
      _showMessage('执行失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _executing = false;
        });
      }
    }
  }

  Future<void> _handleAuthException(AuthException error) async {
    developer.log(
      '[AiCommandPage] handleAuthException message=${error.message} shouldLogout=${error.shouldLogout}',
    );
    if (!mounted) {
      return;
    }
    _showMessage(error.message);
    if (error.shouldLogout && widget.onSessionExpired != null) {
      await widget.onSessionExpired!.call();
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.primaryContainer.withValues(alpha: 0.28),
            palette.background,
          ],
        ),
      ),
      child: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: Column(
          children: [
            _AiChatHeader(
              embedded: widget.embedded,
              busy: _resolving || _executing,
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _AiSuggestionStrip(
                        onTap: (value) => _controller.text = value,
                      ),
                    );
                  }
                  final message = _messages[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AiMessageBubble(
                      message: message,
                      resolving: _resolving,
                      executing: _executing,
                      onExecute: message.canExecute
                          ? () => _execute(message)
                          : null,
                    ),
                  );
                },
              ),
            ),
            _AiComposer(
              controller: _controller,
              enabled: !_resolving && !_executing,
              onSend: _send,
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(backgroundColor: palette.background, body: body);
  }

  String _labelForResult(AiCommandResult result) {
    if (result.requiresConfirmation) {
      return '待决策';
    }
    if ((result.clarificationQuestion ?? '').trim().isNotEmpty ||
        result.missingSlots.isNotEmpty) {
      return '待补充';
    }
    return '解析完成';
  }

  _AiMessageState _stateForStage(String? stage) {
    switch (stage) {
      case 'waiting_confirmation':
        return _AiMessageState.waitingDecision;
      case 'completed':
        return _AiMessageState.completed;
      case 'parsing':
      case 'loading_context':
      case 'planning':
      case 'accepted':
      default:
        return _AiMessageState.idle;
    }
  }

  _AiMessageState _stateForResult(AiCommandResult result) {
    if (result.requiresConfirmation) {
      return _AiMessageState.waitingDecision;
    }
    if ((result.clarificationQuestion ?? '').trim().isNotEmpty ||
        result.missingSlots.isNotEmpty) {
      return _AiMessageState.waitingDecision;
    }
    return _AiMessageState.completed;
  }

  String _labelForStage(String? stage) {
    switch (stage) {
      case 'accepted':
        return '已接收';
      case 'parsing':
        return '解析中';
      case 'loading_context':
        return '加载上下文';
      case 'planning':
        return '生成计划';
      case 'waiting_confirmation':
        return '待决策';
      case 'completed':
        return '解析完成';
      default:
        return '处理中';
    }
  }

  String _detailForResult(AiCommandResolveResponse resolved) {
    final result = resolved.result;
    if (result.requiresConfirmation) {
      return result.confirmationMessage ?? result.userMessage;
    }
    if ((result.clarificationQuestion ?? '').trim().isNotEmpty) {
      return result.clarificationQuestion!;
    }
    if (result.answer?.trim().isNotEmpty == true) {
      return result.answer!;
    }
    return result.userMessage;
  }

  String _executionSummary(AiCommandExecuteResponse executed) {
    if (!executed.executed) {
      return '执行未完成';
    }
    if (executed.affectedItemCount == 0) {
      return '计划已执行';
    }
    return '已执行 ${executed.affectedItemCount} 项变更';
  }
}

enum _AiChatRole { user, assistant, status }

enum _AiMessageState { idle, waitingDecision, executing, completed, error }

class _AiChatMessage {
  _AiChatMessage._({
    required this.role,
    required this.text,
    this.label = '',
    this.detail = '',
    this.resolved,
  }) : state = _AiMessageState.idle;

  factory _AiChatMessage.user({required String text}) {
    return _AiChatMessage._(role: _AiChatRole.user, text: text);
  }

  factory _AiChatMessage.assistant({required String text}) {
    return _AiChatMessage._(role: _AiChatRole.assistant, text: text);
  }

  factory _AiChatMessage.status({
    required String label,
    required String detail,
  }) {
    return _AiChatMessage._(
      role: _AiChatRole.status,
      text: '',
      label: label,
      detail: detail,
    );
  }

  factory _AiChatMessage.resolved(AiCommandResolveResponse resolved) {
    return _AiChatMessage._(
      role: _AiChatRole.assistant,
      text: resolved.result.userMessage.trim().isNotEmpty
          ? resolved.result.userMessage
          : resolved.result.summary,
      resolved: resolved,
    );
  }

  final _AiChatRole role;
  String text;
  String label;
  String detail;
  _AiMessageState state;
  AiCommandResolveResponse? resolved;
  AiCommandVerifyResponse? verified;
  AiCommandExecuteResponse? executed;

  bool get canExecute =>
      resolved?.confirmation != null &&
      state != _AiMessageState.executing &&
      state != _AiMessageState.completed;
}

class _AiChatHeader extends StatelessWidget {
  const _AiChatHeader({required this.embedded, required this.busy});

  final bool embedded;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, embedded ? 8 : 16, 16, 8),
      child: AppSurfaceCard(
        borderRadius: 20,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.primaryContainer.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.smart_toy_rounded, color: palette.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 助理',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    busy ? '正在处理当前指令' : '聊天式操作提醒、清单与闪念',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!embedded)
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiSuggestionStrip extends StatelessWidget {
  const _AiSuggestionStrip({required this.onTap});

  final ValueChanged<String> onTap;

  static const _suggestions = <String>[
    '今天有哪些提醒？',
    '把今天所有提醒标记完成',
    '新增明天早上九点产品会议',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => _AiSuggestionChip(
          label: _suggestions[index],
          onTap: () => onTap(_suggestions[index]),
        ),
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemCount: _suggestions.length,
      ),
    );
  }
}

class _AiSuggestionChip extends StatelessWidget {
  const _AiSuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppChoiceChip(
      label: label,
      selected: false,
      onTap: onTap,
      horizontalPadding: 12,
      verticalPadding: 8,
      textStyle: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _AiMessageBubble extends StatelessWidget {
  const _AiMessageBubble({
    required this.message,
    required this.resolving,
    required this.executing,
    this.onExecute,
  });

  final _AiChatMessage message;
  final bool resolving;
  final bool executing;
  final VoidCallback? onExecute;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final isUser = message.role == _AiChatRole.user;
    final isStatus = message.role == _AiChatRole.status;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final backgroundColor = isUser
        ? palette.primary
        : isStatus
        ? palette.surfaceContainerLow
        : palette.surface;
    final textColor = isUser ? palette.onPrimary : palette.onSurface;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isUser
                  ? palette.primary
                  : palette.outline.withValues(alpha: 0.7),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.text.trim().isNotEmpty)
                Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: textColor,
                    fontWeight: isUser ? FontWeight.w700 : FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              if (isStatus) ...[
                Row(
                  children: [
                    _AiStatePill(state: message.state, label: message.label),
                    const SizedBox(width: 8),
                    if (message.state == _AiMessageState.executing ||
                        (message.state == _AiMessageState.idle && resolving))
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  message.detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
              if (message.resolved != null) ...[
                if (message.text.trim().isNotEmpty) const SizedBox(height: 10),
                _ResolvedSummaryCard(
                  resolved: message.resolved!,
                  executing: executing,
                  onExecute: onExecute,
                ),
              ],
              if (message.executed != null) ...[
                const SizedBox(height: 10),
                _ExecutedSummaryCard(executed: message.executed!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AiStatePill extends StatelessWidget {
  const _AiStatePill({required this.state, required this.label});

  final _AiMessageState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    late final Color backgroundColor;
    late final Color foregroundColor;
    switch (state) {
      case _AiMessageState.waitingDecision:
        backgroundColor = palette.warningContainer.withValues(alpha: 0.75);
        foregroundColor = palette.onWarningContainer;
        break;
      case _AiMessageState.executing:
        backgroundColor = palette.primaryContainer.withValues(alpha: 0.75);
        foregroundColor = palette.primary;
        break;
      case _AiMessageState.completed:
        backgroundColor = palette.successContainer.withValues(alpha: 0.75);
        foregroundColor = palette.onSuccessContainer;
        break;
      case _AiMessageState.error:
        backgroundColor = palette.errorContainer.withValues(alpha: 0.75);
        foregroundColor = palette.onErrorContainer;
        break;
      case _AiMessageState.idle:
        backgroundColor = palette.surface;
        foregroundColor = palette.onSurface;
        break;
    }
    return AppInlineChip(
      label: label,
      textColor: foregroundColor,
      backgroundColor: backgroundColor,
    );
  }
}

class _ResolvedSummaryCard extends StatelessWidget {
  const _ResolvedSummaryCard({
    required this.resolved,
    required this.executing,
    this.onExecute,
  });

  final AiCommandResolveResponse resolved;
  final bool executing;
  final VoidCallback? onExecute;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final result = resolved.result;
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: palette.textMuted, height: 1.45);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.summary,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if ((result.answer ?? '').trim().isNotEmpty)
            Text(result.answer!, style: bodyStyle)
          else if ((result.clarificationQuestion ?? '').trim().isNotEmpty)
            Text(result.clarificationQuestion!, style: bodyStyle)
          else
            Text(result.userMessage, style: bodyStyle),
          if (result.missingSlots.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.missingSlots
                  .map(
                    (item) => AppInlineChip(
                      label: item,
                      textColor: palette.onWarningContainer,
                      backgroundColor: palette.warningContainer,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (result.plan.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...result.plan.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlanStepRow(step: step),
              ),
            ),
          ],
          if (resolved.confirmation != null) ...[
            const SizedBox(height: 12),
            Text(
              '待确认至 ${_formatDateTime(resolved.confirmation!.expiresAt)}',
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: executing ? null : onExecute,
                child: Text(executing ? '执行中...' : '确认执行'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanStepRow extends StatelessWidget {
  const _PlanStepRow({required this.step});

  final AiCommandPlanStep step;
  static const List<String> _previewFieldOrder = <String>[
    '标题',
    '时间',
    '状态',
    '重复',
    '循环截止',
    '提前提醒',
    '通知',
    '清单',
    '分组',
    '标签',
    '备注',
    '结果',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.primaryContainer.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${step.step}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.summary,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                step.reason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                  height: 1.4,
                ),
              ),
              if (step.previewItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...step.previewItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PreviewItemCard(
                      item: item,
                      fieldOrder: _previewFieldOrder,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewItemCard extends StatelessWidget {
  const _PreviewItemCard({required this.item, required this.fieldOrder});

  final AiCommandPreviewItem item;
  final List<String> fieldOrder;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final keys = <String>{
      ...item.before.keys,
      ...item.after.keys,
    }.toList()
      ..retainWhere((key) => (item.before[key] ?? '') != (item.after[key] ?? ''))
      ..sort((a, b) {
        final left = fieldOrder.indexOf(a);
        final right = fieldOrder.indexOf(b);
        if (left == -1 && right == -1) {
          return a.compareTo(b);
        }
        if (left == -1) {
          return 1;
        }
        if (right == -1) {
          return -1;
        }
        return left.compareTo(right);
      });
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title.isEmpty ? '未命名提醒' : item.title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...keys.map((key) {
            final before = item.before[key];
            final after = item.after[key];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${before ?? '—'} → ${after ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ExecutedSummaryCard extends StatelessWidget {
  const _ExecutedSummaryCard({required this.executed});

  final AiCommandExecuteResponse executed;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.successContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            executed.executed ? '执行完成' : '执行未完成',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onSuccessContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '动作：${executed.action}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.onSuccessContainer),
          ),
          if (executed.resultSummaryLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              executed.resultSummaryLines.join('\n'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.onSuccessContainer.withValues(alpha: 0.86),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiComposer extends StatelessWidget {
  const _AiComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: AppSurfaceCard(
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '输入提醒指令，例如：明天 9 点提醒我开会',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: enabled ? onSend : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(50, 50),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: palette.primary,
                  foregroundColor: palette.onPrimary,
                ),
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return DateFormat('MM-dd HH:mm').format(parsed.toLocal());
}
