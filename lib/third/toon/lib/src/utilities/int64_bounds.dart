/// Minimum value for a 64-bit integer.
const int int64Min = -9223372036854775808;

/// Maximum value for a 64-bit integer.
const int int64Max = 9223372036854775807;

/// Checks if a [num] value is within the range of a 64-bit integer.
bool isInInt64Range(num value) => value >= int64Min && value <= int64Max;
