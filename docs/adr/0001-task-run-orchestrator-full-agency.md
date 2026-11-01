# Task Run executes via a full-agency background Orchestrator session

> Status: retired. The home task board and its Task Run entry point have been removed. The decision below records historical behavior and does not apply to the retained AI execution queue, video generation tasks, or chat Todo.

A **Task** is run by launching the **Chat Orchestrator** in the background as an ordinary `chat` session seeded with the task, with its full tool set — it can read *and* edit the novel workspace autonomously. We chose this over a propose-only run (the cautious path that **Dreaming** takes) because a Task Run is the user *explicitly* delegating work ("go do this"), which is a different contract from Dreaming proactively analyzing and proposing. The run is observable and interruptible (the session is inspectable and listed in normal chat history), so full agency is bounded by visibility rather than by withholding write access.

## Consequences

- Task Runs and Dreaming now sit on opposite sides of the "silent edit" line on purpose: Dreaming proposes (`Dreaming Insight Card`), a Task Run acts. This deviation from the app's review-first default is deliberate and must not be "fixed" by making Task Runs propose-only.
- A run only moves the Task to `doing`; it never auto-closes. The user reviews the **Task Run Session** and closes (or reopens) the Task by hand, so a failed or abandoned run is never silently reported as done (Fail-loud).
- A Task must be bound to a novel before it can run, because the Orchestrator session lives in a novel's workspace; an unbound task prompts for a novel at run time.
