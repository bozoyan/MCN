# Relation history uses structured state snapshots

Keep a relation's current type, status, and evidence in ordinary columns.
Store its history in a `change_logs` column containing a JSON array with a
fixed structure, rather than introducing a separate history table. History
supports per-relation inspection and restoration; it does not participate in
relation search, filtering, or graph traversal, as specified in
[ADR 0037](0037-relation-search-matches-current-state-only.md).

Preserve an initial state and append a complete state snapshot for each
subsequent story change. The JSON is a defined snapshot format with these
fields, not arbitrary metadata:

| Field | JSON type / values | Meaning |
|---|---|---|
| id | string | Stable snapshot ID, independent of its array position. |
| kind | "baseline" / "change" | Initial retained state or subsequent story change. |
| relation_type | string | The primary relation type in this state. |
| status | "active" / "ended" | Whether this relation holds in this state. |
| proof | string | Complete supporting evidence for this state. |
| chapter_id | string or null | Evidence chapter; mutually exclusive with scene_id. |
| scene_id | string or null | Evidence scene; mutually exclusive with chapter_id. |
| reason | string | Reason for the change; may be empty for a baseline. |
| recorded_at | UTC ISO 8601 string | Recording timestamp, with the legacy baseline rule below. |

All fields are present; absent evidence references use null. The evidence
references may both be null. Recording time is not the time an event occurred
in the story. IDs and recording times are assigned by the service rather than
accepted as a client-authored history array.

There is deliberately no deleted_at field in either snapshots or the relation
table. The confirmed format uses physical removal from the array, not a hidden
soft-delete marker. kind remains part of the format independently of deletion:
a baseline is not individually removable, while a change is removable under
the rules in ADR 0038. Deleting an entirely mistaken initial relation removes
the parent row and its full history.

For a legacy relation with no history, the first actual change captures an
initial snapshot with recorded_at equal to the row's pre-change updated_at,
then appends the new change with the current operation time in the same
transaction. The captured timestamp describes the last update of the retained
state, not its original establishment in the story. Display it as the initial
record's original update time. Do not substitute created_at or migration time.
For a newly created relation, the initial snapshot and the row's created_at
and updated_at share the same operation time. Snapshot order follows array
position rather than timestamp sorting.

Full snapshots let the UI derive transitions from adjacent remaining states.
Mistaken entries are physically removed from the JSON array, with no deletion
marker or appended correction entry. Deleting a parent relation hard-deletes
the row and its embedded history; neither model introduces a soft-delete field.
Deleting an intermediate mistaken snapshot therefore does not invalidate
later snapshots or change the current state. Deleting the latest mistaken
change restores the preceding snapshot into the current columns, following
[ADR 0038](0038-relation-transitions-preserve-record-identity.md).

Changing the current columns and the snapshot array is one atomic operation.
Ordinary reads and graph searches use the current columns; explicitly
restoring a prior state reads its snapshot and writes the current columns in
that same transaction.

Snapshots retain story states, not a correction audit trail. Edit may correct
the latest snapshot's state fields in place together with the current columns;
it preserves the snapshot ID, kind, recorded_at, and reason and does not append
an entry. Earlier snapshots are unchanged. With an empty legacy history, Edit
updates only the current row; the first later Write captures a baseline from
that corrected row and its pre-Write updated_at. Whole-array writes and direct
edits to individual historical resources remain unavailable to clients.

This chooses simpler per-record storage over independently queryable history.
Historical filtering or graph reconstruction would require revisiting this
decision rather than silently making business queries depend on JSON history.
