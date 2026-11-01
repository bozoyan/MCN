# Relation transitions preserve record identity

An explicit transition such as lovers becoming friends updates the existing
relation's type while preserving its ID and active status. The previous state
and the evidence for the transition remain in that relation's change history.
Ending the old record and creating a new one would split a continuous history
across records without serving the chosen current-state search behavior.

When the evidence establishes only termination, retain the former type and
mark the relation ended; do not infer a new relationship.

The recommended authoring convention is one relation record per entity pair:
look for an existing record and prefer updating it instead of creating another
record for each relation type. This is a recommendation, not a database
uniqueness constraint or a mandate to consolidate existing data. Existing
multiple records for a pair remain supported; do not automatically merge,
delete, or arbitrarily choose one as the authoritative record. This supersedes
the earlier recommendation to create separate records for concurrent types.

An explicit resumption, such as former lovers getting back together, restores
the existing ended relation to active status and appends the resumption's
reason and evidence to its history. The earlier termination remains visible;
the active relation reappears in the graph and GraphSearch. Resumption requires
evidence that this specific relation is being restored, not merely a match of
participants. It does not merge other legacy records between them.

Change history records actual story changes only. Mistaken content is removed,
not preserved as a story transition or followed by an appended correction
event. Do not introduce a correction-log category. This rejects the earlier
proposal to keep both story changes and recording corrections in the history.

Use Write to record an actual change and append a snapshot. Use Edit to correct
one current field without appending history; do not add a record_change switch.
Editable current fields are relation_type, status, proof, chapter_id, and
scene_id. Validate the resulting type, status, and evidence references. Fields
not targeted by Edit retain their values, including evidence locations, and a
correction does not require a new change reason. Endpoints and historical
snapshot resources remain non-editable.

An Edit updates the current columns and the corresponding fields of the latest
snapshot in one transaction, retaining that snapshot's ID, kind, recorded_at,
and reason. Earlier snapshots and the history length remain unchanged. When a
legacy relation has no history, Edit changes only the current row and does not
initialize a baseline. The row's updated_at advances normally. A wholly false
change is removed using the deletion behavior below rather than rewritten as
a different story event.

Deleting the most recent erroneous change also restores the relation's state
immediately before that change. Removing the change and restoring the current
state form one atomic operation, so the history cannot be corrected while the
current relation remains erroneous. This does not append a correction event.
Deleting an earlier erroneous change preserves subsequent confirmed changes
and the current state. The displayed history connects the remaining valid
states without retaining the erroneous intermediate state. For example,
friend -> enemy (mistaken) -> lover becomes friend -> lover, with lover still
current.

Relation deletion retains the existing hard-delete behavior, explicitly
confirmed by the user on 2026-09-24. Deleting a relation removes the row and its
embedded history; deleting a mistaken history entry removes it from the JSON
array. Do not add deleted_at columns or snapshot tombstones. Ending a relation
still means retaining the row with status ended. The exception is limited to
relation data and is recorded in the project's data-deletion rule; it does not
authorize an unsolicited cleanup of existing data during this design session.

Each record retains one primary `relation_type`. Other simultaneous meanings
belong in its supporting explanation, not additional type values. For example,
brothers who become enemies can have `enemy` as the primary type and describe
their kinship and conflict in the evidence. Type filtering matches `enemy`,
not `sibling`, for that record. This deliberately favors the existing scalar
model over exhaustive multi-type querying; it does not rewrite legacy records.

The physical history format is defined in
[ADR 0039](0039-relation-history-uses-structured-snapshots.md).
