# Virtual novelId for Remote Assistant Sessions

> **Superseded by [ADR-0006](0006-remote-assistant-app-db-persistence.md).** The sentinel only persists the session row; messages live in per-novel content DBs, so this option never delivered the history persistence it was justified by. Remote Assistant conversations now persist in dedicated app-DB tables (`assistant_sessions` / `assistant_messages`).

Remote Assistant Sessions are cross-novel (the Assistant reads across novels and routes work via Task Runs), but `AiChatSessions.novelId` is a non-null column. We need to persist Remote Assistant Sessions in the existing table. We decided to store them in `AiChatSessions` with a virtual `novelId` sentinel value (a recognizable constant, not a real novel reference).

## Considered Options

- **Make novelId nullable** (schema migration + null-checks everywhere): rejected as more invasive — touches the schema and every `novelId` consumer.
- **New table for Remote Assistant Sessions**: rejected as duplicating persistence logic — two CRUD paths for chat sessions.
- **In-memory only**: rejected as losing history — the user can't review Remote Assistant conversations on desktop.
- **Virtual novelId** (chosen): lowest invasiveness, no migration, same CRUD path; risk is sentinel handling at consumers.

## Consequences

- Remote Assistant Sessions appear in the same table as novel-bound sessions. UI queries that list sessions by novel must filter out the sentinel.
- The sentinel is a schema-level convention, not a type-level guarantee. Future code must remember to check via a helper (e.g., `isRemoteAssistantNovelId(novelId)`).
- Audit of all `novelId` consumers is required before implementation to avoid runtime "novel not found" errors.
- If we later need multiple Remote Assistant Sessions per user (e.g., one per Remote Channel), the sentinel scheme must extend (e.g., `remote:<channel>:<userId>`).
