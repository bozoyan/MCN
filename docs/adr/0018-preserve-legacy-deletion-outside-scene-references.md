# Preserve legacy deletion outside scene references

Screenplay Scenes introduce durable Character and Location references that must not be left dangling, so deletion is rejected while an active Scene uses the entity. We deliberately limit this new protection to Scene references: when none exist, relation, canvas, location-hierarchy, and map cleanup retain their established behavior, keeping deletion unchanged for existing novel workspaces.

## Considered Options

- Replace all Character and Location deletion with a universal in-use rejection.
- Add protection only for active Scene references and preserve legacy cleanup elsewhere.
