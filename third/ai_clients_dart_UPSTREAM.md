# ai_clients_dart upstream

- Repository: `git@github.com:davidmigloz/ai_clients_dart.git`
- Vendored commit: `d1ed6b2429934ab27553bbb07d1728271e33952f`
- Commit date: 2026-07-21T22:26:46+02:00
- Vendored on: 2026-07-25

The complete tracked contents of the upstream repository are stored in
`third/ai_clients_dart/` without its `.git` metadata. Reveric currently uses:

- `packages/anthropic_sdk_dart`
- `packages/googleai_dart`
- `packages/open_responses`
- `packages/openai_dart`

The initial vendoring commit preserved upstream source unchanged. The following
commit prunes the vendored tree to Reveric's currently used API surface:

- OpenAI: Chat Completions (including streaming) and Embeddings
- Anthropic: Messages (including streaming)
- Gemini: Generate Content (including streaming) and Embed Content
- OpenResponses: Responses (including streaming)

Future updates should compare the desired upstream commit with
`d1ed6b2429934ab27553bbb07d1728271e33952f`, then reapply only the API surface
listed above.
