// 职责: 定义子 agent 委派、传话与停止工具的静态契约。
// 关联文件:
//   lib/shared/models/subagent.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/spawn_agent_handler.dart
// ignore_for_file: use_null_aware_elements
part of 'tools.dart';

const String spawnAgentToolName = 'SpawnAgent';
const String sendAgentMessageToolName = 'SendAgentMessage';
const String stopAgentToolName = 'StopAgent';
const String forkAgentToolName = 'ForkAgent';

const _spawnAgentInputSchema = {
  'type': 'object',
  'properties': {
    'agent': {
      'type': 'string',
      'description': '要使用的子 agent 名称，取 <available_subagents> 中 <name> 的值。',
    },
    'name': {
      'type': 'string',
      'description':
          '为本次子 agent 起的名字。优先遵循用户的命名规则；用户未指定时，推荐使用知名网文作者或其他作者的笔名。同一批子 agent 尽量使用不同名字。',
    },
    'task': {
      'type': 'string',
      'description':
          '子 agent 的任务描述。必须写清目标与资源位置（路径 / ID / 字段路径）、必要背景、本次临时要求与已确定的取舍、允许修改的范围、选定技能的准确名称、验收条件和交付形式。子 agent 不自动继承主对话或已加载的技能正文；用户自定义规则会单独提供，无需全文重复。',
    },
    'background': {
      'type': 'boolean',
      'default': true,
      'description':
          '是否后台执行。默认 true，先返回任务身份，完成后自动通知。短任务且下一步立即依赖其结果时可设为 false，等待并返回最终结果。',
    },
  },
  'required': ['agent', 'name', 'task'],
  'additionalProperties': false,
};

const _spawnAgentDescription = '''
为独立任务创建新的子 agent 会话。

同步执行等待最终结果；后台执行先返回，完成或失败后自动通知。启动成功不代表任务完成。独立任务适合并行推进，或需要让用户继续交流时，优先后台执行。用户明确要求等待时遵从；后台任务未完成且没有其他工作时，结束当前回复等待通知。

适用场景：任务可独立定义和验证、不需要与主对话持续交互（如资料检索、内容核验、事实提取、独立撰写等）；并行执行多个独立子任务可提升整体效率；需多轮递进式处理的任务可分步推进；委派的通信成本低于任务本身的执行成本。

不适用场景：需要子 agent 直接与用户来回确认的任务。

操作要求：按职责从 <available_subagents> 中挑最匹配的 SubAgent；SubAgent 返回结果后由你整合校验、必要时再次行动，不要把 SubAgent 报告原样转交用户。''';

const _sendAgentMessageDescription =
    '向子 agent 补充要求，或继续同一任务的纠错、复审。accepted 仅表示已接收，结果以完成通知为准。';

const _sendAgentMessageInputSchema = {
  'type': 'object',
  'properties': {
    'session_id': {'type': 'string', 'description': '目标子会话的 session_id。'},
    'message': {'type': 'string', 'description': '本次追加的要求和必要背景。'},
  },
  'required': ['session_id', 'message'],
  'additionalProperties': false,
};

const _stopAgentDescription = '请求停止指定子 agent 的当前任务。返回只确认停止请求已接收，最终状态以任务实际结束为准。';

const _stopAgentInputSchema = {
  'type': 'object',
  'properties': {
    'session_id': {'type': 'string', 'description': '目标子会话的 session_id。'},
  },
  'required': ['session_id'],
  'additionalProperties': false,
};

const Map<String, dynamic> forkAgentSchema = {
  'type': 'object',
  'properties': {
    'task': {
      'type': 'string',
      'description':
          'The task description / prompt for the forked agent. Keep it focused and self-contained.',
    },
  },
  'required': ['task'],
  'additionalProperties': false,
};
