# Local MCP SDK adaptation

Source: [mcp_dart 2.4.3](https://pub.dev/packages/mcp_dart/versions/2.4.3), with its original LICENSE and package version. Only runtime sources are vendored.

`StreamableHttpClientTransportOptions.oauthRedirectUriValidator` optionally admits an explicitly registered native redirect URI. Its absence preserves the upstream HTTPS/loopback-only behavior. User information and fragments remain forbidden independently of the callback. Endpoint trust validation, PKCE generation, state/issuer checks and token exchange remain in the SDK.

Reveric opts in only to `ai.reveric://mcp/oauth/callback`, with no port, user information, query or fragment. This keeps Android browser callbacks compatible with the native application registration.

Regression coverage lives in the application's MCP OAuth tests, including a mobile callback transaction across tool-connection background suspension. Do not remove the override until the replacement SDK provides this boundary and passes those tests.

## Opaque tool metadata

Tool descriptors retain arbitrary `_meta` extension keys and JSON values unchanged. At this boundary the SDK checks only that `_meta`, when present, is a JSON object. Tool metadata is not interpreted as the request protocol envelope, so it must not prevent discovery because of vendor naming conventions or extension-specific value formats. Tool schemas and metadata outside tool descriptors retain their original validation, including protocol version, progress, and reserved trace-context checks. Protocol negotiation is unchanged.

The application's HTTP adapter tests verify unknown metadata and schemas round-trip intact while non-object tool metadata is rejected. Generic metadata validation remains strict at other boundaries. The Android exact native redirect adaptation above remains in place.

## Windows stdio command shims

The native stdio transport uses Dart's system-shell launch on Windows so commands such as `npx` resolve `.cmd` shims through `cmd.exe`. Other platforms still launch the executable directly. Environment inheritance remains enabled by default; Reveric passes only user overrides and, on macOS, the PATH read from the user's login shell.

If closing stdin does not stop the Windows server, shutdown uses `taskkill /T /F` to stop the command interpreter and its descendants together.

## Dynamic Client Registration results

The SDK stores Dynamic Client Registration results only inside the transport. A provider that also implements `OAuthClientRegistrationListener` receives the issued `client_id`, `client_secret` and `token_endpoint_auth_method` right after a successful registration and before the authorization redirect. Providers that do not implement the listener keep the upstream behavior. Registration, validation and token exchange are unchanged.

Reveric stores these values next to the OAuth grant, separately from the user-configured pre-registered client ID. Refresh and revocation run outside the transport and authenticate as the registered client, so confidential clients keep working after the access token expires. The application's MCP OAuth tests cover a confidential registered client across code exchange, refresh, revocation and a second login.
