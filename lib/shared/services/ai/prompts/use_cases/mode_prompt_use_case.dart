// 职责: Mode Prompt Use Case — 构建 monologue/roleplay/theater/council 等特殊模式的 system prompt 和 task prompt
// 关联文件:
//   lib/shared/services/ai/prompts/ai_prompt_service.dart
//   lib/shared/services/ai/monologue_orchestrator.dart
//   lib/shared/services/ai/roleplay_orchestrator.dart
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/services/ai/agent_council_orchestrator.dart

import '../../../../models/ai_chat_models.dart';
import '../../../../models/content_kind.dart';
import '../../../ai/prompt_template.dart';
import '../../../ai/prompts/prompt_id.dart';
import '../../../ai/prompts/prompt_fragments.dart';
import '../../../ai/prompts/prompt_renderer.dart';
import 'agent_prompt_use_case.dart';

class ModePromptUseCase {
  const ModePromptUseCase({this.renderer, this.contentKind = contentKindNovel});

  final String contentKind;

  final PromptRenderer? renderer;

  // ---------------------------------------------------------------------------
  // Monologue
  // ---------------------------------------------------------------------------

  String monologueSystem({
    required String characterName,
    required String characterRole,
    String? characterSummary,
    String? characterDescription,
    String? systemPrompt,
  }) {
    final variables = _baseCharacterVariables(
      characterName: characterName,
      characterRole: characterRole,
      characterSummary: characterSummary,
      characterDescription: characterDescription,
    );
    final rendered = systemPrompt != null && systemPrompt.isNotEmpty
        ? _renderString(systemPrompt, variables)
        : _render(PromptId.agentMonologueNarrator, variables);
    return _appendPathSchema(rendered);
  }

  // ---------------------------------------------------------------------------
  // Roleplay
  // ---------------------------------------------------------------------------

  String roleplaySystem({
    required String characterName,
    required String characterRole,
    String? characterSummary,
    String? characterDescription,
    String? systemPrompt,
  }) {
    final variables = _baseCharacterVariables(
      characterName: characterName,
      characterRole: characterRole,
      characterSummary: characterSummary,
      characterDescription: characterDescription,
    );
    final rendered = systemPrompt != null && systemPrompt.isNotEmpty
        ? _renderString(systemPrompt, variables)
        : _render(PromptId.agentRoleplayMaster, variables);
    return _appendPathSchema(rendered);
  }

  // ---------------------------------------------------------------------------
  // Theater
  // ---------------------------------------------------------------------------

  String theaterSystem({
    required String characterName,
    required String characterId,
    required String characterRole,
    String? characterSummary,
    String? characterDescription,
    required String otherParticipants,
    String? systemPrompt,
  }) {
    final variables = _baseCharacterVariables(
      characterName: characterName,
      characterRole: characterRole,
      characterSummary: characterSummary,
      characterDescription: characterDescription,
    );
    variables['character_id'] = characterId;
    variables['other_participants'] = otherParticipants;
    final rendered = systemPrompt != null && systemPrompt.isNotEmpty
        ? _renderString(systemPrompt, variables)
        : _render(PromptId.agentTheaterActor, variables);
    return _appendPathSchema(rendered);
  }

  String theaterLine({
    required String sceneDescription,
    required String participantName,
    required String participantCharacterId,
    required int round,
    String? priorLines,
  }) {
    return _render(PromptId.taskTheaterLine, {
      'scene_description': sceneDescription,
      if (priorLines != null && priorLines.isNotEmpty)
        'prior_lines': priorLines,
      'participant_name': participantName,
      'participant_character_id': participantCharacterId,
      'round': round.toString(),
      'is_first_speaker': priorLines == null || priorLines.isEmpty
          ? 'true'
          : null,
    });
  }

  // ---------------------------------------------------------------------------
  // Council
  // ---------------------------------------------------------------------------

  String councilSystem({
    required String basePrompt,
    required AiSessionContext context,
  }) {
    final buffer = StringBuffer(
      AgentPromptUseCase(
        renderer: renderer,
      ).renderPromptTemplate(basePrompt, context: context),
    );
    buffer.writeln();
    buffer.writeln(PromptFragments.workContext(context));
    buffer.writeln();
    buffer.writeln(PromptFragments.toolUseGuidelines());
    buffer.writeln();
    buffer.writeln(PromptFragments.pathSchemaBlock(kind: context.contentKind));
    return buffer.toString().trim();
  }

  /// [newMessages] 用于对话里已有前文的成员，只含其上次发言之后的内容；
  /// 此时 [priorRounds] 为 null。
  String councilRound({
    required String topic,
    required String participantName,
    required String participantDescription,
    required int round,
    String? otherMembers,
    String? priorRounds,
    String? newMessages,
  }) {
    return _render(PromptId.taskCouncilRound, {
      'topic': topic,
      if (priorRounds != null && priorRounds.isNotEmpty)
        'prior_rounds': priorRounds,
      if (newMessages != null && newMessages.isNotEmpty)
        'new_messages': newMessages,
      if (otherMembers != null && otherMembers.isNotEmpty)
        'other_members': otherMembers,
      'participant_name': participantName,
      'participant_description': participantDescription,
      'round': round.toString(),
      'has_prior_rounds': priorRounds != null && priorRounds.isNotEmpty
          ? 'true'
          : null,
    });
  }

  String councilSummary({
    required String topic,
    required String discussionHistory,
  }) {
    return _render(PromptId.taskCouncilSummary, {
      'topic': topic,
      'discussion_history': discussionHistory,
    });
  }

  String councilSummarizerSystem() {
    return _render(PromptId.systemCouncilSummarizer);
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _baseCharacterVariables({
    required String characterName,
    required String characterRole,
    String? characterSummary,
    String? characterDescription,
  }) {
    return {
      'character_name': characterName,
      'character_role': characterRole,
      if (characterSummary != null && characterSummary.isNotEmpty)
        'character_summary': characterSummary,
      if (characterDescription != null && characterDescription.isNotEmpty)
        'character_description': characterDescription,
    };
  }

  String _appendPathSchema(String prompt) {
    return [
      prompt,
      PromptFragments.toolUseGuidelines(),
      PromptFragments.pathSchemaBlock(kind: contentKind),
    ].join('\n\n').trim();
  }

  String _render(String promptId, [Map<String, dynamic> variables = const {}]) {
    final promptRenderer =
        renderer ?? PromptRenderer(templates: PromptTemplateService.instance);
    return promptRenderer.render(promptId, variables);
  }

  String _renderString(
    String template, [
    Map<String, dynamic> variables = const {},
  ]) {
    final promptRenderer = renderer;
    if (promptRenderer != null) {
      return promptRenderer.renderString(template, variables);
    }
    return PromptTemplateService.renderString(template, variables);
  }
}
