import 'package:meta/meta.dart';

import '../common/copy_with_sentinel.dart';
import '../responses/config/reasoning_effort.dart';
import '../tools/tool.dart';
import '../tools/tool_choice.dart';
import 'chat_message.dart';

/// Request for creating a chat completion.
///
/// This is the primary request model for the chat completions API.
/// It contains all the parameters needed to generate a response.
///
/// ## Example
///
/// ```dart
/// final request = ChatCompletionCreateRequest(
///   model: 'gpt-4o',
///   messages: [
///     ChatMessage.system('You are a helpful assistant.'),
///     ChatMessage.user('Hello!'),
///   ],
///   temperature: 0.7,
///   maxTokens: 1000,
/// );
///
/// final response = await client.chat.completions.create(request);
/// ```
@immutable
class ChatCompletionCreateRequest {
  /// Creates a [ChatCompletionCreateRequest].
  const ChatCompletionCreateRequest({
    required this.model,
    required this.messages,
    this.maxTokens,
    this.maxCompletionTokens,
    this.serviceTier,
    this.temperature,
    this.tools,
    this.toolChoice,
    this.parallelToolCalls,
    this.metadata,
    this.store,
    this.streamOptions,
    this.reasoningEffort,
    this.promptCacheKey,
  });

  /// Creates a [ChatCompletionCreateRequest] from JSON.
  factory ChatCompletionCreateRequest.fromJson(Map<String, dynamic> json) {
    return ChatCompletionCreateRequest(
      model: json['model'] as String,
      messages: (json['messages'] as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      maxTokens: json['max_tokens'] as int?,
      maxCompletionTokens: json['max_completion_tokens'] as int?,
      serviceTier: json['service_tier'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble(),
      tools: (json['tools'] as List<dynamic>?)
          ?.map((e) => Tool.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolChoice: json['tool_choice'] != null
          ? ToolChoice.fromJson(json['tool_choice'])
          : null,
      parallelToolCalls: json['parallel_tool_calls'] as bool?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
      store: json['store'] as bool?,
      streamOptions: json['stream_options'] != null
          ? StreamOptions.fromJson(
              json['stream_options'] as Map<String, dynamic>,
            )
          : null,
      reasoningEffort: json['reasoning_effort'] != null
          ? ReasoningEffort.fromJson(json['reasoning_effort'] as String)
          : null,
      promptCacheKey: json['prompt_cache_key'] as String?,
    );
  }

  /// The model to use for completion.
  ///
  /// Examples: `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, `o1-preview`
  final String model;

  /// The messages to generate a completion for.
  final List<ChatMessage> messages;

  /// Maximum number of tokens to generate.
  ///
  /// Deprecated: Use [maxCompletionTokens] for newer models.
  final int? maxTokens;

  /// Maximum number of tokens to generate (for o1 and newer models).
  final int? maxCompletionTokens;

  /// The service tier to use.
  ///
  /// Can be `auto` or `default`. If not specified, defaults to `auto`.
  final String? serviceTier;

  /// Sampling temperature between 0 and 2.
  ///
  /// Higher values make output more random, lower values more deterministic.
  /// Generally, use either this or topP, not both.
  final double? temperature;

  /// The tools available for the model to call.
  final List<Tool>? tools;

  /// Controls which tool is called.
  ///
  /// Can be:
  /// - `auto`: Let the model decide
  /// - `none`: Don't call any tools
  /// - `required`: Must call a tool
  /// - Specific tool: Force a specific tool
  final ToolChoice? toolChoice;

  /// Whether to enable parallel function calling.
  ///
  /// Defaults to true. Set to false to force sequential tool calls.
  final bool? parallelToolCalls;

  /// Custom metadata to attach to the request.
  ///
  /// Values can be of any type and will be automatically converted to strings
  /// when serialized to JSON, as the API requires string values. Null values
  /// are omitted. After a JSON round-trip (`toJson()` then `fromJson()`), all
  /// metadata values will be strings.
  final Map<String, dynamic>? metadata;

  /// Whether to store this completion for model improvements.
  final bool? store;

  /// Options for streaming responses.
  final StreamOptions? streamOptions;

  /// Controls reasoning effort for reasoning models (o1, o3, o4-mini).
  ///
  /// Higher effort levels may produce better results for complex problems
  /// but take longer to process.
  final ReasoningEffort? reasoningEffort;

  /// Prompt cache key for optimizing cache hit rates.
  ///
  /// Used by OpenAI to cache responses for similar requests.
  /// Replaces the [user] field for caching purposes.
  final String? promptCacheKey;

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    'model': model,
    'messages': messages.map((m) => m.toJson()).toList(),
    if (maxTokens != null) 'max_tokens': maxTokens,
    if (maxCompletionTokens != null)
      'max_completion_tokens': maxCompletionTokens,
    if (serviceTier != null) 'service_tier': serviceTier,
    if (temperature != null) 'temperature': temperature,
    if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
    if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
    if (parallelToolCalls != null) 'parallel_tool_calls': parallelToolCalls,
    if (metadata case final metadata?
        when metadata.values.any((v) => v != null))
      'metadata': {
        for (final MapEntry(:key, :value) in metadata.entries)
          if (value != null) key: value.toString(),
      },
    if (store != null) 'store': store,
    if (streamOptions != null) 'stream_options': streamOptions!.toJson(),
    if (reasoningEffort != null) 'reasoning_effort': reasoningEffort!.toJson(),
    if (promptCacheKey != null) 'prompt_cache_key': promptCacheKey,
  };

  /// Creates a copy with replaced values.
  ChatCompletionCreateRequest copyWith({
    String? model,
    List<ChatMessage>? messages,
    Object? maxTokens = unsetCopyWithValue,
    Object? maxCompletionTokens = unsetCopyWithValue,
    Object? serviceTier = unsetCopyWithValue,
    Object? temperature = unsetCopyWithValue,
    Object? tools = unsetCopyWithValue,
    Object? toolChoice = unsetCopyWithValue,
    Object? parallelToolCalls = unsetCopyWithValue,
    Object? metadata = unsetCopyWithValue,
    Object? store = unsetCopyWithValue,
    Object? streamOptions = unsetCopyWithValue,
    Object? reasoningEffort = unsetCopyWithValue,
    Object? promptCacheKey = unsetCopyWithValue,
  }) {
    return ChatCompletionCreateRequest(
      model: model ?? this.model,
      messages: messages ?? this.messages,
      maxTokens: maxTokens == unsetCopyWithValue
          ? this.maxTokens
          : maxTokens as int?,
      maxCompletionTokens: maxCompletionTokens == unsetCopyWithValue
          ? this.maxCompletionTokens
          : maxCompletionTokens as int?,
      serviceTier: serviceTier == unsetCopyWithValue
          ? this.serviceTier
          : serviceTier as String?,
      temperature: temperature == unsetCopyWithValue
          ? this.temperature
          : temperature as double?,
      tools: tools == unsetCopyWithValue ? this.tools : tools as List<Tool>?,
      toolChoice: toolChoice == unsetCopyWithValue
          ? this.toolChoice
          : toolChoice as ToolChoice?,
      parallelToolCalls: parallelToolCalls == unsetCopyWithValue
          ? this.parallelToolCalls
          : parallelToolCalls as bool?,
      metadata: metadata == unsetCopyWithValue
          ? this.metadata
          : metadata as Map<String, dynamic>?,
      store: store == unsetCopyWithValue ? this.store : store as bool?,
      streamOptions: streamOptions == unsetCopyWithValue
          ? this.streamOptions
          : streamOptions as StreamOptions?,
      reasoningEffort: reasoningEffort == unsetCopyWithValue
          ? this.reasoningEffort
          : reasoningEffort as ReasoningEffort?,
      promptCacheKey: promptCacheKey == unsetCopyWithValue
          ? this.promptCacheKey
          : promptCacheKey as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatCompletionCreateRequest &&
          runtimeType == other.runtimeType &&
          model == other.model &&
          _listEquals(messages, other.messages);

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(model, Object.hashAll(messages));

  @override
  String toString() =>
      'ChatCompletionCreateRequest(model: $model, messages: ${messages.length})';
}

/// Options for streaming responses.
@immutable
class StreamOptions {
  /// Creates [StreamOptions].
  const StreamOptions({this.includeUsage});

  /// Creates [StreamOptions] from JSON.
  factory StreamOptions.fromJson(Map<String, dynamic> json) {
    return StreamOptions(includeUsage: json['include_usage'] as bool?);
  }

  /// Whether to include usage statistics in the stream.
  ///
  /// If true, the final chunk will include usage information.
  final bool? includeUsage;

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    if (includeUsage != null) 'include_usage': includeUsage,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamOptions &&
          runtimeType == other.runtimeType &&
          includeUsage == other.includeUsage;

  @override
  int get hashCode => includeUsage.hashCode;

  @override
  String toString() => 'StreamOptions(includeUsage: $includeUsage)';
}
