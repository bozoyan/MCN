# Screenplay writes reference characters only by ID

Character elements accept only a stable `character_id` when written. Reads may include the resolved Character name for comprehension, but writes reject that display field and never resolve names or aliases, avoiding ambiguous matches and silent speaker substitutions.

## Considered Options

- Accept a Character name or alias and resolve it during writes.
- Require `character_id` and keep names read-only.
