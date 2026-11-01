# Relation search matches current state only

Relation search matches the current state of active relations. Users can inspect
an individual relation's change history after opening it, but historical types
and descriptions do not participate in search. For example, a relation that
changed from lover to friend matches friend, not its former lover type.

This boundary keeps ordinary search results aligned with the current relation
and avoids introducing historical search or graph reconstruction merely to
preserve an inspectable account of changes. It permits history to remain
dedicated to display and traceability rather than serving as query state.

The graph defaults to showing active relations. A character's relation list
provides a "show ended" toggle that includes ended records alongside active
ones. Ended records retain their type and display an explicit ended label;
opening a record provides access to its change history. This applies to both
desktop and mobile. The toggle filters the record's current status, not past
states inside its history, and does not add ended edges to the graph.

Reading and searching have distinct scopes. `Read /relations` returns both
active and ended records, with their current status. Reading an individual
relation also remains available after it ends. `GraphSearch` returns only
active relations and traverses only active edges; ended edges cannot connect
an entity to further results at greater depth. Neither operation searches past
states inside change history.

The UI's default hiding of ended relations is a presentation choice, not a
default restriction on `Read /relations`.

## Relation detail presentation

Keep the current relationship information visible: both entities, the primary
relation type, active or ended status, and current supporting explanation with
navigable chapter or scene evidence. Below it, show a collapsed change-history
section with its record count; expand it on demand.

Display history in reverse recording order. Each change shows its before and
after state, reason, and evidence location. Chapter numbers do not determine
story chronology. The states and transitions are backed by the snapshots
defined in [ADR 0039](0039-relation-history-uses-structured-snapshots.md).

Before a history record is deleted, explain the actual effect: deleting the
latest change restores the preceding state and identifies that state in the
confirmation; deleting an earlier change leaves the current relation unchanged.
The underlying deletion rules are defined in
[ADR 0038](0038-relation-transitions-preserve-record-identity.md).

Use the existing relation detail area on desktop and the relation detail panel
on mobile, with the same information and operations on both platforms.
