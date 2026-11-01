/// Checks if a [num] value is within the range of a 64-bit integer.
/// Fallback implementation for unknown targets.
bool isInInt64Range(num value) {
  const double int64Min = -9223372036854775808.0;
  const double int64Max = 9223372036854775807.0;
  return value >= int64Min && value <= int64Max;
}
