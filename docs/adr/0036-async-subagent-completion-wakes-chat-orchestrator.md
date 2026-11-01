---
status: accepted
---

# Async Chat Subagent completion wakes the Chat Orchestrator

When a Chat Subagent completes an asynchronously delegated task, its completion must actively wake the source Chat Orchestrator to process the result without requiring another user message. This supports continuous creative collaboration: the user can discuss the next chapter's outline while a Chat Subagent writes the preceding chapter, and the Chat Orchestrator can bring the completed work back into that discussion.

We chose active wake-up over a completion indicator that waits for the user's next message, because passive notification leaves the user responsible for bringing delegated results back into the conversation.

## Keep the feature small

The feature is background delegation within existing chat: launch a child without holding up the main conversation, send it relevant follow-up instructions, deliver its result back to the Chat Orchestrator, and provide the agreed cancellation controls.

Do not add chapter ownership, resource reservations, or exclusive-writer enforcement for this feature. SpawnAgent currently receives a natural-language task rather than structured write-target ownership, and the user explicitly declined adding that mechanism. Preserve direct writes and restoration to selected historical targets while fixing turn ownership storage in T0. Division of work remains an orchestration responsibility, not a new runtime guarantee against overlapping edits.

## T0: reliable rollback with a simple field diff

Before asynchronous delegation, independently ship the existing chat rollback fix: retain changes across user-message boundaries, coalescing only consecutive edits with the same ownership. Rolling back the second message in A→B→C must restore B, regardless of whether the changes were accepted or committed. Reuse existing fields; do not invent intermediate snapshots for older records that have already been coalesced.

Keep the review UI simple. Show each resource field once, comparing the earliest before-value among that session's reviewable records with the current saved content. Retain the existing line rollback and whole rollback controls. Line rollback restores selected lines to the displayed left side and keeps the other right-side lines; whole rollback restores the displayed target and updates the backing records together. Do not add a revision-history expander, modification-count drill-down, or segmentation by editing source. The UI projection must not replace the original turn records, and its rollback operation must use the displayed field snapshots rather than an arbitrary single change ID. T0 remains useful and independently releasable if asynchronous delegation is postponed or reverted.

## Choosing foreground or background execution

The Chat Orchestrator may choose foreground waiting or background execution based on task dependencies, without requiring the user to explicitly request background mode. Independent work may continue in the background while the main conversation advances; when the next action requires the delegated result, the Chat Orchestrator waits for it. Explicit user instructions to wait or run in the background take precedence.

This gives users a creative collaboration workflow without requiring them to select an execution mode for every delegation. The agreed tool contract adds `background` to SpawnAgent with a default of false. Reusing SpawnAgent with an explicit `session_id` continues an existing subagent conversation; SendAgentMessage adds instructions to a running task, and StopAgent requests cancellation. Do not add separate follow-up or wait tools: synchronous SpawnAgent waits for a result, while background results are delivered automatically.

## Updating a running delegation

The Chat Orchestrator may send additional instructions to a running Chat Subagent when confirmed decisions in the main conversation affect its assignment. The child receives these instructions before its next model request, without interrupting its current response or tool operation.

The Chat Orchestrator selects and communicates the relevant change; the main conversation is not automatically mirrored into the child. This keeps tentative discussion out of the child's instructions while allowing a confirmed change to redirect ongoing work. For example, a decision that a character must survive the first chapter can be sent to the writer while the user continues discussing the second chapter.

## Delivery timing

If the source Chat Orchestrator is idle, completion wakes it immediately. If it is answering a user message, completion is queued for delivery before its next model request, without interrupting the current model response or an executing tool. During an automatically triggered execution, only results attributed to the same originating user message may join that execution; other results wait for their own turn. A result arriving during the final response must still be processed after that response finishes, even if the Chat Orchestrator would otherwise become idle.

We chose this boundary over immediate interruption so a completed background task does not truncate an ongoing reply or cancel a workspace operation in progress.

## Mutation ownership after completion

Attribute the Chat Orchestrator's changes to the user message responsible for its current execution. When completion wakes an idle orchestrator, its review and follow-on edits belong to the user message that originally delegated the task. When completion is consumed while the orchestrator is answering a newer user message, its subsequent edits belong to that current user message. The Chat Subagent's own edits retain their original delegation ownership in both cases.

Group automatic executions by the originating user message and process those groups serially. Results from the same origin may be combined; results from different origins must not share one automatic execution. Determine ownership at delivery, so a result received while a user turn was busy but consumed after that turn ended follows the idle wake-up rule. Accepting a new user message starts that message's ownership boundary; merely queueing it does not.

We chose existing user-message ownership so rolling back the original delegation also rolls back its automatically triggered review, while edits made in response to a newer instruction remain attributable to that instruction. Reuse `sourceTurnId` without adding a database field. Completion notifications have their own message IDs and are recorded as system reminders, not new user requests; their IDs do not replace the user-message ID used for rollback. Rolling back an originating message cancels its affected tasks and invalidates pending notifications before restoring changes and truncating history.

## User cancellation scope

The design distinguishes three user actions:

- **Stop Reply** stops the Chat Orchestrator's current work while background Chat Subagent tasks continue.
- **Stop Subtask** stops one selected Chat Subagent task while other work continues.
- **Stop All** stops the Chat Orchestrator's current work and its running Chat Subagent tasks within the same source chat session. Late notifications from that stopped work must not trigger execution again.

We chose separate controls because interrupting a discussion of the next chapter should not implicitly cancel prose generation for the preceding chapter. Stop All provides an explicit way to stop the whole current collaboration.

## Completion after Stop Reply

Stop Reply does not disable completion-triggered wake-up. A background Chat Subagent task that continues running may still wake the Chat Orchestrator when it completes. The resulting turn processes that completion in the current conversation context; it does not automatically resume the work the user stopped.

This preserves the distinction between stopping the current reply and stopping the whole collaboration. Stop All still suppresses execution triggered by late notifications from the stopped work.

## Existing background execution and application restart

Reuse the existing background-execution choice when leaving an active workspace or chat page; do not introduce a second background-running option for this feature. Both desktop and mobile already offer background execution in their processing-exit flow. Background Delegation adds concurrency within a source conversation and must integrate with that existing page-lifecycle behavior.

Application restart must not automatically resume interrupted delegated work. Background execution while the application remains alive is distinct from restarting execution in a new process. This decision does not authorize new operating-system background privileges or an external worker service.

Current integration points are `handleProcessingExit` in `lib/desktop/pages/novel_editor.dart` and `lib/mobile/pages/novel_chat_page.dart`. The existing "Pause execution" action in that exit flow maps to Stop All for the current source chat session: stop the Chat Orchestrator and its running Chat Subagent tasks, suppress execution triggered by their late notifications, and leave other chat sessions unaffected. Choosing background execution retains the running work under the existing page-exit lifecycle.

## Failure handling and user visibility

A failed background delegation also wakes the Chat Orchestrator with the failure details. The Chat Orchestrator decides whether to retry, adjust the task, or explain the failure to the user. The runtime does not automatically restart the entire delegated task; existing request-level retry behavior is outside this decision.

Users must have an accessible list of currently running background agents and a manual pause action for each agent. Exact placement is an implementation proposal in the [solution document](../solutions/async-chat-subagents.md), not an additional accepted layout decision.

This records agreed design decisions, not an implemented capability or approval to implement the complete feature.

## Cancellation references examined on 2026-09-21

These are research findings, not additional accepted decisions for Reveric. No live cancellation experiments were run.

- **Codex CLI 0.153.4:** the core `interrupt_task` path aborts the addressed Session's active task, without traversing descendant agent threads. The agent-control API also addresses interruption to a specific thread. This establishes the core operation's scope; it does not establish that every desktop/web Stop control sends only that operation. Sources: [session interruption](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/src/session/mod.rs#L4569), [task cancellation](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/src/tasks/mod.rs#L511), [agent control](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/src/agent/control.rs#L355). The [official subagent guide](https://learn.chatgpt.com/docs/agent-configuration/subagents) documents separate subagent controls, with availability varying by client.
- **Claude Code:** the official 2.1.47 changelog explicitly separates Escape interruption of the main thread from stopping background agents. Current documentation provides `x` to stop a selected subagent and `Ctrl+X Ctrl+K` to stop all running background subagents. A subagent stopped by the user cannot be automatically resumed by an agent message; a subagent stopped through the AI's `TaskStop` can be resumed. Sources: [changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#2147), [interactive controls](https://code.claude.com/docs/en/interactive-mode#general-controls), [subagent resumption](https://code.claude.com/docs/en/sub-agents#resume-subagents).
- **OpenCode 1.18.31:** session cancellation first cancels matching background jobs and recursively follows their session/parent-session relationships, before stopping the session runner. Although the background Task launch path returns before installing the foreground abort listener, that alone does not mean background children survive parent-session cancellation. Sources: [session run state](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/session/run-state.ts#L77), [Task launch](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/task.ts#L284).
- **DSH, provisionally interpreted as DeepSeek Harness:** for continuable background children, ownership transfers at inbox acceptance; later caller cancellation does not cancel the accepted turn or dispose the child. Explicit interruption targets the current turn, preserves unclaimed queued work and descendants, and leaves the agent available for later messages. Full runtime teardown is a separate operation. This finding is scoped to continuable children, not every provider or one-shot mode. Source: [official subagent contract at ddefc45f](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/docs/subsystems/subagent.md#continuable-children-and-activations).
