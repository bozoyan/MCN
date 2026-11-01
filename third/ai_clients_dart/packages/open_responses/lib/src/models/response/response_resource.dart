import 'package:meta/meta.dart';

import '../common/copy_with_sentinel.dart';
import '../common/equality_helpers.dart';
import '../items/output_item.dart';
import '../metadata/response_status.dart';
import '../metadata/service_tier.dart';
import 'incomplete_details.dart';
import 'usage.dart';

/// A response resource from the API.
@immutable
class ResponseResource {
  /// Unique identifier.
  final String? id;

  /// Object type. Always "response".
  final String object;

  /// The response status.
  final ResponseStatus? status;

  /// The output items.
  final List<OutputItem>? output;

  /// Token usage statistics.
  final Usage? usage;

  /// Details about why the response is incomplete.
  final IncompleteDetails? incompleteDetails;

  /// The service tier used.
  final ServiceTier? serviceTier;

  /// User-provided metadata.
  final Map<String, String>? metadata;

  /// A key used for prompt cache reads/writes.
  final String? promptCacheKey;

  /// Creates a [ResponseResource].
  const ResponseResource({
    this.id,
    this.object = 'response',
    this.status,
    this.output,
    this.usage,
    this.incompleteDetails,
    this.serviceTier,
    this.metadata,
    this.promptCacheKey,
  });

  /// Creates a [ResponseResource] from JSON.
  factory ResponseResource.fromJson(Map<String, dynamic> json) {
    return ResponseResource(
      id: json['id'] as String?,
      object: json['object'] as String? ?? 'response',
      status: json['status'] == null
          ? null
          : ResponseStatus.fromJson(json['status'] as String),
      output: (json['output'] as List?)
          ?.map((e) => OutputItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? Usage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      incompleteDetails: json['incomplete_details'] != null
          ? IncompleteDetails.fromJson(
              json['incomplete_details'] as Map<String, dynamic>,
            )
          : null,
      serviceTier: json['service_tier'] != null
          ? ServiceTier.fromJson(json['service_tier'] as String)
          : null,
      metadata: (json['metadata'] as Map?)?.cast<String, String>(),
      promptCacheKey: json['prompt_cache_key'] as String?,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'object': object,
    if (status != null) 'status': status!.toJson(),
    if (output != null) 'output': output!.map((e) => e.toJson()).toList(),
    if (usage != null) 'usage': usage!.toJson(),
    if (incompleteDetails != null)
      'incomplete_details': incompleteDetails!.toJson(),
    if (serviceTier != null) 'service_tier': serviceTier!.toJson(),
    if (metadata != null) 'metadata': metadata,
    if (promptCacheKey != null) 'prompt_cache_key': promptCacheKey,
  };

  /// Creates a copy with replaced values.
  ResponseResource copyWith({
    Object? id = unsetCopyWithValue,
    String? object,
    Object? status = unsetCopyWithValue,
    Object? output = unsetCopyWithValue,
    Object? usage = unsetCopyWithValue,
    Object? incompleteDetails = unsetCopyWithValue,
    Object? serviceTier = unsetCopyWithValue,
    Object? metadata = unsetCopyWithValue,
    Object? promptCacheKey = unsetCopyWithValue,
  }) {
    return ResponseResource(
      id: id == unsetCopyWithValue ? this.id : id as String?,
      object: object ?? this.object,
      status: status == unsetCopyWithValue
          ? this.status
          : status as ResponseStatus?,
      output: output == unsetCopyWithValue
          ? this.output
          : output as List<OutputItem>?,
      usage: usage == unsetCopyWithValue ? this.usage : usage as Usage?,
      incompleteDetails: incompleteDetails == unsetCopyWithValue
          ? this.incompleteDetails
          : incompleteDetails as IncompleteDetails?,
      serviceTier: serviceTier == unsetCopyWithValue
          ? this.serviceTier
          : serviceTier as ServiceTier?,
      metadata: metadata == unsetCopyWithValue
          ? this.metadata
          : metadata as Map<String, String>?,
      promptCacheKey: promptCacheKey == unsetCopyWithValue
          ? this.promptCacheKey
          : promptCacheKey as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponseResource &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          object == other.object &&
          status == other.status &&
          listsEqual(output, other.output) &&
          usage == other.usage &&
          incompleteDetails == other.incompleteDetails &&
          serviceTier == other.serviceTier &&
          mapsEqual(metadata, other.metadata) &&
          promptCacheKey == other.promptCacheKey;

  @override
  int get hashCode => Object.hashAll([
    id,
    object,
    status,
    listHash(output),
    usage,
    incompleteDetails,
    serviceTier,
    mapHash(metadata),
    promptCacheKey,
  ]);

  @override
  String toString() => 'ResponseResource(id: $id, status: $status, ...)';
}
