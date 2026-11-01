# Screenplay text review applies changes immediately

Screenplay synopsis and element changes use the existing working-overlay lifecycle: staging writes the proposed value immediately while retaining the original value, acceptance records the already-applied value in history, and rejection restores the original value. This keeps screenplay editing consistent with the established overlay and lets subsequent AI operations read and extend the current staged screenplay; the trade-off is that unaccepted AI text is visible in the live editor until the user rejects it.

## Considered Options

- Keep proposed screenplay text outside the live tables until acceptance.
- Apply proposed screenplay text immediately and use the overlay as reversible review state.
