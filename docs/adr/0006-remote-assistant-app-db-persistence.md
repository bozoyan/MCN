# Remote Assistant conversations persist in dedicated app-DB tables

Supersedes [ADR-0004](0004-virtual-novelid-remote-assistant-sessions.md).

Chat persistence in Reveric is novel-shaped in two places: `AiChatSessions.novelId` is non-null (app DB), and messages live only in per-novel content DBs (`AiChatMessages`) — the turn pipeline (`runHeadlessSessionTurn`, `aiSessionPersistenceServiceProvider`) addresses storage by `novelId + databasePath + Novel`. The Remote Assistant is cross-novel and its conversations must survive app restarts. ADR-0004 chose a virtual `novelId` sentinel on the assumption that persisting the session row preserves history; it does not — messages need a content-DB home, which a sentinel never provides. We decided to persist Remote Assistant conversations in dedicated app-DB tables: `assistant_sessions` (unique on `(channel_type, chat_id)`) and `assistant_messages`, with a new `runRemoteAssistantTurn` entry that reuses the `ChatTurnRunner` kernel but writes to these tables. The runner's novel dependencies become optional; the Assistant path uses a constant in-memory runtime key that never touches the DB.

## Considered Options

- **Virtual novelId sentinel** (ADR-0004, superseded): persists the session row but messages have no home; requires auditing every `novelId` consumer; rejected.
- **Hidden workspace novel** (real `Novels` row + content DB, hidden by type filter): zero pipeline changes, but a fake novel leaks into every novel-listing surface (bookshelf, `list_novels` tool, storage stats/cleanup, delete path) and must be defended by filters forever; rejected as unclean modeling.
- **Nullable novelId**: schema migration plus null-handling at all consumers, and still no message home; rejected.
- **In-memory only**: violates the persistence requirement; rejected.
- **Dedicated app-DB tables** (chosen): no sentinel anywhere, no novel-list filtering, existing chat persistence surfaces are untouched; cost is a second message-persistence path and making `ChatTurnRunner`'s novel context optional.

## Consequences

- Two message-persistence paths exist (novel content DB for novel-scoped chat; app DB for the Assistant). Message serialization must be shared (`json_serializer.dart`) and locked by tests to prevent drift.
- `ChatTurnRunner` novel dependencies (`novelId` / `databasePath` / `novelSnapshot`) become optional; existing novel-scoped callers keep current signatures and behavior (regression: `test/shared/services/ai/`).
- The desktop chat panel cannot show Assistant transcripts in V1 (they are not `AiChatSessions` rows). Data is persisted and available; the planned future extension is chatting with the Assistant directly on the app home page (`channel_type = 'local'` + fixed chat_id on the same tables), which also delivers transcript review.
- `session_subscriptions.session_id` continues to reference only run sessions (`AiChatSessions`); Assistant sessions need no subscription rows.
- ADR-0002's "persistent per remote user" session model is realized by the `(channel_type, chat_id)` unique key; additional channels or a local entry point extend without schema change.
