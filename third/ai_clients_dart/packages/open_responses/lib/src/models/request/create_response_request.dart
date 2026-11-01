import 'package:meta/meta.dart';

import '../common/copy_with_sentinel.dart';
import '../common/equality_helpers.dart';
import '../items/item.dart';
import '../metadata/include.dart';
import '../metadata/service_tier.dart';
import '../tools/tool.dart';
import '../tools/tool_choice.dart';
import 'reasoning_config.dart';

/// Type-safe input for a response request.
///
/// Can be either a simple text string or a list of input items.
sealed class ResponseInput {
  /// Creates a [ResponseInput].
  const ResponseInput();

  /// Creates a text input.
  static ResponseInput text(String text) => ResponseTextInput(text);

  /// Creates an items input.
  static ResponseInput items(List<Item> items) => ResponseItemsInput(items);

  /// Creates a [ResponseInput] from JSON.
  factory ResponseInput.fromJson(Object json) {
    if (json is String) return ResponseTextInput(json);
    if (json is List) {
      return ResponseItemsInput(
        json.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList(),
      );
    }
    throw FormatException('Invalid ResponseInput format: $json');
  }

  /// Converts to JSON.
  Object toJson();
}

/// A simple text input.
@immutable
class ResponseTextInput extends ResponseInput {
  /// The text input.
  final String text;

  /// Creates a [ResponseTextInput].
  const ResponseTextInput(this.text);

  @override
  Object toJson() => text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponseTextInput &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ResponseTextInput($text)';
}

/// A list of items input.
@immutable
class ResponseItemsInput extends ResponseInput {
  /// The input items.
  final List<Item> items;

  /// Creates a [ResponseItemsInput].
  const ResponseItemsInput(this.items);

  @override
  Object toJson() => items.map((e) => e.toJson()).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponseItemsInput &&
          runtimeType == other.runtimeType &&
          listsEqual(items, other.items);

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => 'ResponseItemsInput($items)';
}

/// Request to create a response.
@immutable
class CreateResponseRequest {
  /// The model to use for generation.
  final String model;

  /// The input for the response.
  ///
  /// Can be a [ResponseTextInput] (for simple text) or [ResponseItemsInput]
  /// (for complex messages).
  final ResponseInput input;

  /// System-level instructions for the model.
  final String? instructions;

  /// Tools available to the model.
  final List<Tool>? tools;

  /// How the model should choose which tool to call.
  final ToolChoice? toolChoice;

  /// Maximum tokens to generate.
  final int? maxOutputTokens;

  /// Sampling temperature (0.0 - 2.0).
  final double? temperature;

  /// Whether to stream the response.
  final bool? stream;

  /// Configuration for reasoning models.
  final ReasoningConfig? reasoning;

  /// Whether the model may call multiple tools in parallel.
  final bool? parallelToolCalls;

  /// Service tier for request processing.
  final ServiceTier? serviceTier;

  /// User-defined metadata.
  final Map<String, String>? metadata;

  /// Additional data to include in response.
  final List<Include>? include;

  /// Whether to store the response for later retrieval.
  final bool? store;

  /// A key to use when reading from or writing to the prompt cache.
  final String? promptCacheKey;

  /// Creates a [CreateResponseRequest].
  const CreateResponseRequest({
    required this.model,
    required this.input,
    this.instructions,
    this.tools,
    this.toolChoice,
    this.maxOutputTokens,
    this.temperature,
    this.stream,
    this.reasoning,
    this.parallelToolCalls,
    this.serviceTier,
    this.metadata,
    this.include,
    this.store,
    this.promptCacheKey,
  });

  /// Creates a simple text request.
  factory CreateResponseRequest.text({
    required String model,
    required String input,
    String? instructions,
    int? maxOutputTokens,
    double? temperature,
  }) {
    return CreateResponseRequest(
      model: model,
      input: ResponseTextInput(input),
      instructions: instructions,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
    );
  }

  /// Creates a [CreateResponseRequest] from JSON.
  factory CreateResponseRequest.fromJson(Map<String, dynamic> json) {
    return CreateResponseRequest(
      model: json['model'] as String,
      input: ResponseInput.fromJson(json['input']),
      instructions: json['instructions'] as String?,
      tools: (json['tools'] as List?)
          ?.map((e) => Tool.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolChoice: json['tool_choice'] != null
          ? ToolChoice.fromJson(json['tool_choice'])
          : null,
      maxOutputTokens: json['max_output_tokens'] as int?,
      temperature: (json['temperature'] as num?)?.toDouble(),
      stream: json['stream'] as bool?,
      reasoning: json['reasoning'] != null
          ? ReasoningConfig.fromJson(json['reasoning'] as Map<String, dynamic>)
          : null,
      parallelToolCalls: json['parallel_tool_calls'] as bool?,
      serviceTier: json['service_tier'] != null
          ? ServiceTier.fromJson(json['service_tier'] as String)
          : null,
      metadata: (json['metadata'] as Map?)?.cast<String, String>(),
      include: (json['include'] as List?)
          ?.map((e) => Include.fromJson(e as String))
          .toList(),
      store: json['store'] as bool?,
      promptCacheKey: json['prompt_cache_key'] as String?,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    'model': model,
    'input': input.toJson(),
    if (instructions != null) 'instructions': instructions,
    if (tools != null) 'tools': tools!.map((e) => e.toJson()).toList(),
    if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
    if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
    if (temperature != null) 'temperature': temperature,
    if (stream != null) 'stream': stream,
    if (reasoning != null) 'reasoning': reasoning!.toJson(),
    if (parallelToolCalls != null) 'parallel_tool_calls': parallelToolCalls,
    if (serviceTier != null) 'service_tier': serviceTier!.toJson(),
    if (metadata != null) 'metadata': metadata,
    if (include != null) 'include': include!.map((e) => e.toJson()).toList(),
    if (store != null) 'store': store,
    if (promptCacheKey != null) 'prompt_cache_key': promptCacheKey,
  };

  /// Creates a copy with replaced values.
  CreateResponseRequest copyWith({
    String? model,
    ResponseInput? input,
    Object? instructions = unsetCopyWithValue,
    Object? tools = unsetCopyWithValue,
    Object? toolChoice = unsetCopyWithValue,
    Object? maxOutputTokens = unsetCopyWithValue,
    Object? temperature = unsetCopyWithValue,
    Object? stream = unsetCopyWithValue,
    Object? reasoning = unsetCopyWithValue,
    Object? parallelToolCalls = unsetCopyWithValue,
    Object? serviceTier = unsetCopyWithValue,
    Object? metadata = unsetCopyWithValue,
    Object? include = unsetCopyWithValue,
    Object? store = unsetCopyWithValue,
    Object? promptCacheKey = unsetCopyWithValue,
  }) {
    return CreateResponseRequest(
      model: model ?? this.model,
      input: input ?? this.input,
      instructions: instructions == unsetCopyWithValue
          ? this.instructions
          : instructions as String?,
      tools: tools == unsetCopyWithValue ? this.tools : tools as List<Tool>?,
      toolChoice: toolChoice == unsetCopyWithValue
          ? this.toolChoice
          : toolChoice as ToolChoice?,
      maxOutputTokens: maxOutputTokens == unsetCopyWithValue
          ? this.maxOutputTokens
          : maxOutputTokens as int?,
      temperature: temperature == unsetCopyWithValue
          ? this.temperature
          : temperature as double?,
      stream: stream == unsetCopyWithValue ? this.stream : stream as bool?,
      reasoning: reasoning == unsetCopyWithValue
          ? this.reasoning
          : reasoning as ReasoningConfig?,
      parallelToolCalls: parallelToolCalls == unsetCopyWithValue
          ? this.parallelToolCalls
          : parallelToolCalls as bool?,
      serviceTier: serviceTier == unsetCopyWithValue
          ? this.serviceTier
          : serviceTier as ServiceTier?,
      metadata: metadata == unsetCopyWithValue
          ? this.metadata
          : metadata as Map<String, String>?,
      include: include == unsetCopyWithValue
          ? this.include
          : include as List<Include>?,
      store: store == unsetCopyWithValue ? this.store : store as bool?,
      promptCacheKey: promptCacheKey == unsetCopyWithValue
          ? this.promptCacheKey
          : promptCacheKey as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateResponseRequest &&
          runtimeType == other.runtimeType &&
          model == other.model &&
          input == other.input &&
          instructions == other.instructions &&
          listsEqual(tools, other.tools) &&
          toolChoice == other.toolChoice &&
          maxOutputTokens == other.maxOutputTokens &&
          temperature == other.temperature &&
          stream == other.stream &&
          reasoning == other.reasoning &&
          parallelToolCalls == other.parallelToolCalls &&
          serviceTier == other.serviceTier &&
          mapsEqual(metadata, other.metadata) &&
          listsEqual(include, other.include) &&
          store == other.store &&
          promptCacheKey == other.promptCacheKey;

  @override
  int get hashCode => Object.hashAll([
    model,
    input,
    instructions,
    listHash(tools),
    toolChoice,
    maxOutputTokens,
    temperature,
    stream,
    reasoning,
    parallelToolCalls,
    serviceTier,
    mapHash(metadata),
    listHash(include),
    store,
    promptCacheKey,
  ]);

  @override
  String toString() =>
      'CreateResponseRequest('
      'model: $model, input: $input, instructions: $instructions, '
      'tools: $tools, toolChoice: $toolChoice, '
      'maxOutputTokens: $maxOutputTokens, temperature: $temperature, '
      'stream: $stream, reasoning: $reasoning, '
      'parallelToolCalls: $parallelToolCalls, serviceTier: $serviceTier, '
      'metadata: $metadata, include: $include, store: $store, '
      'promptCacheKey: $promptCacheKey)';
}
