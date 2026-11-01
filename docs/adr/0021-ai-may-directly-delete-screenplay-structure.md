# AI may directly delete screenplay structure

AI may remove Episodes, Scenes, and Beats directly in the first release, even though there is no user-facing recycle bin and structural changes do not enter the text-review overlay. We accept this authority so AI can complete ordinary structural editing workflows; removals remain soft deletions, use the same cascades as UI deletion, and cannot remove the last Episode of a Season. Season deletion is intentionally excluded because its larger cascade requires explicit UI review, as defined by ADR-0028.

## Considered Options

- Restrict structural deletion to the user-confirmed UI.
- Allow AI structural deletion to commit immediately.
