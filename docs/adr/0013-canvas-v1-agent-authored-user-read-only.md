# Canvas V1: agent-authored, user read-only, inside NovelEditor

We are adding an infinite-pan **Canvas** as a NovelEditor mode (novel-scoped, zero or more per novel, desktop first) whose purpose is a mood/story board, but in V1 the **Chat Orchestrator** is the sole editor: it places **Canvas Reference Nodes** pointing to existing Persisted Workspace Entries, draws **Canvas Edges**, and writes **Canvas Stickies**, all on the currently active Canvas, streamed live. The user is a read-only viewer of canvas content (nodes, edges, stickies); the Canvas entity itself (create/switch/delete/rename) may be managed by either the user or the agent. Human editing of canvas content and human-agent co-authoring are deferred to V2.

We chose agent-authored-and-user-read-only over human-driven or co-authored V1 because the feature's value is making the agent's organization of the novel visible, and V1 co-authoring would force us to solve concurrent edits, conflict resolution, and permission boundaries before the agent-side value is proven. Sub-nodes and edges are stored in their own tables (`canvas_nodes`, `canvas_edges`), not in Canvas metadata, per the project's no-metadata-for-business-data rule; Canvas Reference Nodes point to Persisted Workspace Entries without copying content, and Canvas Stickies are Canvas-owned (not independent workspace entries) in V1.

## Consequences

- Canvas entity CRUD (create/switch/delete/rename) is available to both user and agent; only canvas content is user-read-only in V1. The first Canvas in a novel may be created by either, depending on intent.
- V1 has no in-canvas content editing; resource content is edited in its own editor, not on the Canvas.
- The agent toolset must cover at least: add/move node, add edge, add sticky, and must target the currently active Canvas.
- Live streaming requires the Canvas UI to update as the agent works (nodes appear/move, edges draw, stickies write) — this is not a batch-apply model.
- The active Canvas must be resolvable as the agent's target, which implies the Canvas-as-active-view is part of the Active Workspace Target story (to be confirmed in a follow-up).
- In-canvas editing (Canvas Reference Node edits flowing to the source entry) and human-agent co-authoring are explicitly open for V2, not silently dropped.
