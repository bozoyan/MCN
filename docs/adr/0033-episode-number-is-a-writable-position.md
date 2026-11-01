# Episode number is a writable position

`episode_number` is both readable and writable. Reading returns an Episode's current one-based position within its Season; writing a value in `1..active Episode count` moves that Episode to the requested position and transactionally shifts the intervening Episodes so numbering remains contiguous. Writing the current number is a no-op, an out-of-range value returns `invalid_episode_number`, and stable references continue to use `episode_id`.
