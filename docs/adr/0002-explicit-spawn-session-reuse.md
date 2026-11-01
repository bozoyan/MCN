# SpawnAgent reuses sessions only by explicit session id

SpawnAgent may continue a prior **Spawn Session** only when the tool call provides that session's id. We chose explicit reuse over automatic "latest subagent session" selection because reuse carries hidden working context and should be a deliberate continuation, not an implicit side effect of choosing the same Chat Subagent name.

## Consequences

- A SpawnAgent call without a session id keeps the existing isolated behavior and creates a new Spawn Session.
- Reuse appends to the existing Spawn Session instead of forking it.
- Current SubAgent prompt, model, and tool configuration are allowed to run against an older Spawn Session.
