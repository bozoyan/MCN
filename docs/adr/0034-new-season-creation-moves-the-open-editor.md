# New Season creation moves the open editor

After a Season and its initial Episode are created, an open desktop or mobile editor selects the new Season and Episode and clears its current Scene. UI creation flushes the prior Scene before starting and leaves the old selection unchanged on failure. AI creation reports the new IDs so the editor follows as well, but the active AI turn retains its pre-creation frozen Current Season; same-turn operations in the new Season must use the IDs returned by Create, and the next turn adopts the new workspace selection.
