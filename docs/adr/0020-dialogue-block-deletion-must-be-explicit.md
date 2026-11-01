# Dialogue block deletion must be explicit

Deleting a Character cue is rejected while Parenthetical or Dialogue elements still depend on it. We require an explicit whole-block deletion or reassignment instead of cascading from a single cue deletion, because the first release has no recycle bin and an implicit cascade could destroy substantial screenplay text.

## Considered Options

- Cascade deletion from the Character cue through its dependent elements.
- Reject cue-only deletion and require an explicit block operation.
