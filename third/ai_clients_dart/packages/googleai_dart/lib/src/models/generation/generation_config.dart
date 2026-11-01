import '../copy_with_sentinel.dart';
import 'thinking_config.dart';

/// Configuration options for model generation.
class GenerationConfig {
  /// Maximum number of tokens to generate.
  final int? maxOutputTokens;

  /// Controls randomness (0.0 to 2.0).
  final double? temperature;

  /// Thinking configuration.
  final ThinkingConfig? thinkingConfig;

  /// Response JSON schema for structured output.
  final Map<String, dynamic>? responseJsonSchema;

  /// Creates a [GenerationConfig].
  const GenerationConfig({
    this.maxOutputTokens,
    this.temperature,
    this.thinkingConfig,
    this.responseJsonSchema,
  });

  /// Creates a [GenerationConfig] from JSON.
  factory GenerationConfig.fromJson(Map<String, dynamic> json) =>
      GenerationConfig(
        maxOutputTokens: json['maxOutputTokens'] as int?,
        temperature: (json['temperature'] as num?)?.toDouble(),
        thinkingConfig: json['thinkingConfig'] != null
            ? ThinkingConfig.fromJson(
                json['thinkingConfig'] as Map<String, dynamic>,
              )
            : null,
        responseJsonSchema: json['responseJsonSchema'] as Map<String, dynamic>?,
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
    if (temperature != null) 'temperature': temperature,
    if (thinkingConfig != null) 'thinkingConfig': thinkingConfig!.toJson(),
    if (responseJsonSchema != null) 'responseJsonSchema': responseJsonSchema,
  };

  /// Creates a copy with replaced values.
  GenerationConfig copyWith({
    Object? maxOutputTokens = unsetCopyWithValue,
    Object? temperature = unsetCopyWithValue,
    Object? thinkingConfig = unsetCopyWithValue,
    Object? responseJsonSchema = unsetCopyWithValue,
  }) {
    return GenerationConfig(
      maxOutputTokens: maxOutputTokens == unsetCopyWithValue
          ? this.maxOutputTokens
          : maxOutputTokens as int?,
      temperature: temperature == unsetCopyWithValue
          ? this.temperature
          : temperature as double?,
      thinkingConfig: thinkingConfig == unsetCopyWithValue
          ? this.thinkingConfig
          : thinkingConfig as ThinkingConfig?,
      responseJsonSchema: responseJsonSchema == unsetCopyWithValue
          ? this.responseJsonSchema
          : responseJsonSchema as Map<String, dynamic>?,
    );
  }
}
