import 'types.dart';

/// Options for encoding to TOON format.
class EncodeOptions {
  /// Number of spaces per indentation level (default: 2).
  final int indent;

  /// Delimiter for array values and tabular rows (default: ',').
  final String delimiter;

  /// Optional marker to prefix array lengths (default: null).
  /// Set to '#' to enable length marker.
  final String? lengthMarker;

  const EncodeOptions({
    this.indent = 2,
    this.delimiter = ',',
    this.lengthMarker,
  }) : assert(indent > 0, 'indent must be positive');

  /// Resolves encode options with defaults.
  ResolvedEncodeOptions resolve() {
    return ResolvedEncodeOptions(
      indent: indent,
      delimiter: delimiter,
      lengthMarker: lengthMarker,
    );
  }
}

/// Options for decoding from TOON format.
class DecodeOptions {
  /// Expected number of spaces per indentation level (default: 2).
  final int indent;

  /// Enable strict validation (default: true).
  final bool strict;

  const DecodeOptions({this.indent = 2, this.strict = true})
    : assert(indent > 0, 'indent must be positive');

  /// Resolves decode options with defaults.
  ResolvedDecodeOptions resolve() {
    return ResolvedDecodeOptions(indent: indent, strict: strict);
  }
}
