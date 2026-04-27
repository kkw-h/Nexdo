import 'package:flutter_test/flutter_test.dart';
import 'package:nexdo/src/features/ai_commands/domain/ai_command_models.dart';

void main() {
  group('ai_command_execute_response', () {
    test('counts nested reminder results by affected reminders', () {
      final response = AiCommandExecuteResponse.fromMap({
        'executed': true,
        'action': 'update_reminder',
        'result': [
          [
            {'id': 'a', 'title': '晨会'},
            {'id': 'b', 'title': '复盘'},
          ],
        ],
        'claims': <String, dynamic>{},
      });

      expect(response.affectedItemCount, 2);
      expect(response.resultSummaryLines, <String>['晨会', '复盘']);
    });

    test('counts delete result by reminder_ids length', () {
      final response = AiCommandExecuteResponse.fromMap({
        'executed': true,
        'action': 'delete_reminder',
        'result': [
          {
            'deleted': true,
            'reminder_ids': ['a', 'b'],
          },
        ],
        'claims': <String, dynamic>{},
      });

      expect(response.affectedItemCount, 2);
      expect(response.resultSummaryLines, <String>['已删除 2 条提醒']);
    });
  });
}
