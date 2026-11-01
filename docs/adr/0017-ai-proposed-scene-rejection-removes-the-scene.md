# Rejecting an AI-proposed scene removes the scene

AI scene creation is recorded as a single scene-level create change even though most structural operations commit directly. Like Chapter creation, one Create call writes the Scene structure, Synopsis, and initial Elements, and those initial values appear only in the create preview rather than as separate field changes. We choose this exception because an AI-created scene and its proposed prose are one authoring unit: rejecting the create change must soft-delete the scene and its associated data, rather than leave an empty scene for the writer to clean up. Later edits to the created Scene remain ordinary field changes; no separate atomic Scene-proposal layer is introduced.

## Considered Options

- Commit AI scene creation as an irreversible structural operation.
- Record AI scene creation as a reviewable scene-level create change.
