// In JS, ints are 64-bit floats, where the maximum safe integer is 2^53.
// However, for TOON, we must preserve the format's semantics:
bool isInInt64Range(num value) {
  // Compare against limits as double (safe approximation in JS).
  const double int64MinAsDouble = -9223372036854775808.0;
  const double int64MaxAsDouble =
      9223372036854775807.0; // JS rounds this, but it's valid as a double literal.
  return value >= int64MinAsDouble && value <= int64MaxAsDouble;
}
