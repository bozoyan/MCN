import 'dart:math';

/// Generates a RFC4122 compliant UUID (version 4).
///
/// A version 4 UUID is randomly generated. This implementation follows the
/// format specified in RFC4122 with the appropriate bits set to identify
/// it as a version 4, variant 1 UUID.
///
/// Returns a string representation of the UUID in the format:
/// 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
String generateUUID() {
  // Constants for UUID version 4
  const int uuidVersion = 0x40; // Version 4 (random)
  const int uuidVariant = 0x80; // Variant 1 (RFC4122)

  final random = Random.secure();
  final bytes = List<int>.generate(16, (i) => random.nextInt(256));

  // Set the version bits (bits 6-7 of 7th byte to 0b01)
  bytes[6] = (bytes[6] & 0x0f) | uuidVersion;

  // Set the variant bits (bits 6-7 of 9th byte to 0b10)
  bytes[8] = (bytes[8] & 0x3f) | uuidVariant;

  // Convert to hex and format with hyphens
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
