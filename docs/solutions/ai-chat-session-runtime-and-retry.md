# AI Chat Session Runtime and Retry

## Problem

The chat retry flow originally removed the failed assistant message before
starting a new request. Because the retry button lived inside that assistant
message widget, removing the message could unmount the widget while the retry
async chain still held its `BuildContext` and `WidgetRef`.

The same path also rebuilt prompt context for every request and eagerly loaded
large novel context that the current chat system prompt did not directly use.

A later requirement changes the lifecycle boundary: one chat session may keep
running while the user switches to another session or creates a new one. Multiple
chat sessions must be able to run at the same time.

## Goals

- Retry in place by reusing the failed assistant message instead of deleting it.
- Keep system prompt context lightweight.
- Let the agent read heavy novel context through tools on demand.
- Keep in-flight requests alive across expand/collapse, session selection, and
  new-session creation.
- Allow multiple chat sessions to run concurrently.
- Make explicit user cancellation, session deletion, and runtime disposal the
  only lifecycle boundaries that cancel an active chat request.
- Keep the council, theater, roleplay, and monologue session-scoped agent cache
  work aligned with the chat runtime model.

## V1: Panel-Local Agent Lifecycle

V1 kept the chat `Agent` as panel-local runtime state managed by hooks.
`useChatAgent` owned the cached `Agent` reference through
`AiChatPanelState.chatAgent`, with the chat session id as the lifecycle key.
Provider, model, agent profile, prompt context, rules, and available subagents
were treated as mutable session configuration and did not tear down an in-flight
agent.

When the session id changed while a request was active, the hook recorded a
deferred reset instead of calling `cancel()` immediately. The current stream was
allowed to finish, then the cached reference was cleared without cancelling the
already-completed agent. Explicit user cancellation, session close, and panel
disposal still cancelled the active agent.

Retry in V1 called
`startStreamingMessage(messageId: failedAssistantMessageId)`, clearing and
marking the same assistant message as streaming. Stream deltas, tool blocks,
image blocks, ask-user blocks, and finalization targeted the active streaming
assistant message rather than assuming the last message was always the stream
target.

### Why V1 Is Not Enough

V1 fixes retry-in-place and reduces unnecessary agent rebuilds, but its
lifecycle owner is still the visible `AiChatPanel`. That is the wrong boundary
for concurrent sessions.

Specific failures:

- Expand/collapse can still unmount or reparent the panel. A panel-local hook
  must then either cancel the active agent or special-case UI transitions.
- Switching from session A to session B changes the single visible
  `aiChatSessionProvider`. A running request for A no longer has a stable state
  target if all stream writes go through the current selected session.
- Creating session B while session A is streaming should not defer-reset or
  detach A's agent. A and B must each own a separate active runtime.
- `BuildContext.mounted` is a UI lifetime check. It should not decide whether a
  session-level request continues.
- The hook model can only represent one active chat agent per panel. It cannot
  represent N active sessions in the background.

The V1 retry and prompt-context changes remain useful. The V1 lifecycle
ownership model should not be extended further.

## V2: Session-Scoped Runtime Registry

V2 moves chat request ownership from `AiChatPanel` into a session-scoped runtime.
The UI selects which session to display; the runtime owns which sessions are
processing.

### Core Model

Introduce a runtime registry keyed by `sessionId`.

Each session runtime owns:

- cached `Agent`
- active `AiClient`
- request sequence / active request id
- processing state
- cancellation state
- queued follow-up / next-turn state
- pending ask-user completers
- active tool execution count
- retry target message id, when retrying in place

The registry API should make the session id explicit:

- `send(sessionId, input, contextSnapshot)`
- `retry(sessionId, assistantMessageId, contextSnapshot)`
- `cancel(sessionId)`
- `cancelAllForNovel(novelId)` if the editor/page is disposed
- `disposeSession(sessionId)` when a session is deleted or no longer retained

The current `activeAiSessionId` remains a UI pointer only. Changing it must not
cancel or reset any runtime.

### State Writes

Streaming writes must target a specific session, not the current selected
session.

The chat session state layer needs one of these shapes:

- a family provider, for example `aiChatSessionProvider(sessionId)`, where each
  session has independent message state; or
- a session store / registry that exposes actions such as
  `appendTextDelta(sessionId, delta)` and `endStreaming(sessionId)`.

The important constraint is that runtime A never writes through "whatever
session is currently selected". Every stream event carries or closes over the
source `sessionId`.

Persisted messages should be saved with the same explicit `sessionId`. If the
visible session is different, the UI list/history can still observe persisted or
cached changes for the background session.

### UI Responsibilities

`AiChatPanel` keeps only local UI state:

- composer controller
- focus node
- scroll position
- overlay/menu state
- temporary attached references and draft UI state

`AiChatPanel` no longer owns:

- `Agent`
- active `AiClient`
- request sequence
- in-flight cancellation state
- pending ask-user completers

The panel watches the runtime state for the selected `sessionId` to render
processing indicators and enable/disable controls. Session history can also
watch runtime summaries to show which background sessions are still processing.

### Expand / Collapse

Expand/collapse becomes a pure layout change. It may rebuild, unmount, or move
the panel without affecting the runtime. No `GlobalKey`, `isExpandTransition`,
or hook-dispose exception is required for correctness.

### Retry

Keep the V1 retry-in-place behavior:

- do not remove the failed assistant message;
- mark the same assistant message as streaming;
- clear retry metadata before streaming;
- route deltas, tool blocks, image blocks, ask-user blocks, errors, and final
  usage to that message.

V2 changes only the target addressing: retry updates
`(sessionId, assistantMessageId)`, not "the active streaming message in the
currently selected session".

### Prompt Context

Keep prompt context lightweight. It should contain only fields directly consumed
by the chat prompt or persona templates:

- database path and novel name
- current chapter id/title
- workspace title/content
- current user name
- enabled agent rules

Heavy context remains excluded:

- chapter body
- previous chapter content
- outline entries
- worldbuilding entries
- character profiles
- material notes

Those resources remain available through tools such as `Read`.

### Council / Theater / Roleplay / Monologue

The existing direction for other agent modes remains valid because those modes
already move toward session-scoped agent ownership:

- `RoleplayOrchestrator` and `MonologueOrchestrator` cache their single actor
  `Agent` by `session.id`.
- `AgentCouncilOrchestrator` caches participant agents by
  `session.id + participant.id`.
- `TheaterOrchestrator` caches character agents by
  `session.id + characterId`.
- Provider notifiers create a new orchestrator for a new session, but reuse the
  existing orchestrator for continue/additional-round actions.

The chat runtime should follow the same ownership rule: agents belong to the
session runtime, not to the currently visible widget.

## Migration Plan

1. Keep V1 retry-in-place message APIs, but add explicit session targeting to
   the write path.
2. Add the session runtime registry and move `Agent`, `AiClient`, request
   sequence, cancellation state, pending ask-user completers, and active tool
   execution counters out of `AiChatPanelState`.
3. Change send, retry, and cancel handlers to call the runtime registry with
   `sessionId`.
4. Make stream handlers write to the explicit session target.
5. Update `AiChatPanel` to watch runtime state for the selected session and keep
   only UI-local hook state.
6. Add session-list processing indicators from runtime summaries.
7. Remove `chat_agent_hook.dart` once no runtime state depends on panel hooks.
8. Remove transition-specific cancellation guards such as `isExpandTransition`.

## Expected Impact

- Retrying no longer unmounts the retry button's message widget before the
  retry request starts.
- Normal requests no longer reload large prompt context on every turn.
- Expand/collapse no longer cancels active requests.
- Switching sessions or creating a new session no longer cancels the previous
  session's request.
- Multiple chat sessions can run at the same time.
- Background sessions can keep streaming and update their own messages while
  another session is visible.
- Council/theater additional rounds and roleplay/monologue continuations keep
  their agent conversation context instead of rebuilding from mutable UI state.
- Prompt size stays smaller while preserving environment, rules, persona
  variables, and tool routing context.
