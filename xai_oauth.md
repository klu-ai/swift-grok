# xAI OAuth API Notes

This repo supports an xAI OAuth mode that is separate from Grok web cookie auth. OAuth mode stores a bearer credential from xAI's device-code flow and uses the xAI API base URL for supported commands.

## Auth Mode Selection

`GrokCLIApp.currentAuthMode()` resolves auth in this order:

1. `GROK_AUTH_MODE`, when it parses successfully.
2. A saved `xai-oauth.json` credential.
3. A saved `auth-mode.json` preference.
4. Web cookie auth.

Accepted OAuth aliases are `oauth`, `xai`, `xai-oauth`, and `xai-oauth-api`. Accepted web aliases are `web`, `cookie`, `cookies`, `browser`, and `grok`.

When OAuth credentials exist, the CLI prefers OAuth automatically. Use `GROK_AUTH_MODE=web` to force web-cookie mode for a single command.

## Environment

Default endpoints:

- OAuth discovery: `https://auth.x.ai/.well-known/openid-configuration`
- API base URL: `https://api.x.ai/v1`

Supported environment overrides:

- `GROK_AUTH_MODE`: force `oauth` or `web`.
- `GROK_CONFIG_DIR`: override the config directory that stores credentials.
- `GROK_XAI_OAUTH_CLIENT_ID`: override the OAuth client ID.
- `GROK_XAI_OAUTH_SCOPE`: override requested scopes.
- `GROK_XAI_OAUTH_DISCOVERY_URL`: override discovery.
- `GROK_XAI_API_BASE_URL`: override the API base.
- `GROK_XAI_OAUTH_ALLOW_LOCAL=1`: allow local HTTP endpoints for tests.

Endpoint validation only accepts HTTPS x.ai hosts by default. Local HTTP is allowed only for `localhost`, `127.0.0.1`, or `::1` when local overrides are enabled.

## Device Login Flow

The CLI starts with OpenID discovery:

```http
GET /.well-known/openid-configuration
Accept: application/json
```

Consumed discovery fields:

- `issuer`
- `token_endpoint`
- `device_authorization_endpoint`
- `authorization_endpoint`, decoded but not otherwise used

Then the CLI requests a device code:

```http
POST <device_authorization_endpoint>
Content-Type: application/x-www-form-urlencoded
Accept: application/json

client_id=<client-id>&scope=<scope>
```

Consumed device response fields:

- `device_code`
- `user_code`
- `verification_uri`
- `verification_uri_complete`
- `expires_in`
- `interval`, default `5`, minimum `1`

The CLI prints the verification URL and user code, then polls the token endpoint:

```http
POST <token_endpoint>
Content-Type: application/x-www-form-urlencoded
Accept: application/json

grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=<device-code>&client_id=<client-id>
```

Polling behavior:

- `authorization_pending`: keep polling.
- `slow_down`: add 5 seconds to the polling interval.
- `expired_token`: fail and ask the user to run `grok auth oauth` again.
- `access_denied` or `authorization_denied`: fail as denied.
- Other OAuth errors surface their `error_description` or `error`.

## Token Refresh

Credentials refresh when they expire within 60 seconds:

```http
POST <token_endpoint>
Content-Type: application/x-www-form-urlencoded
Accept: application/json

grant_type=refresh_token&refresh_token=<refresh-token>&client_id=<client-id>
```

If a refresh response omits `refresh_token`, `id_token`, `token_type`, or `scope`, the saved value is preserved.

## Saved Credential

Credentials are saved at:

```text
${GROK_CONFIG_DIR}/xai-oauth.json
```

The file is written atomically, pretty-printed, sorted by key, encoded with ISO8601 dates, and chmodded to `0600`.

Fields:

- `accessToken`
- `refreshToken`
- `idToken`
- `tokenType`
- `scope`
- `expiresAt`
- `obtainedAt`
- `issuer`
- `tokenEndpoint`
- `deviceAuthorizationEndpoint`
- `apiBaseURL`

Do not commit or paste real credential contents.

## API Auth Headers

All xAI API calls use:

```http
Authorization: <tokenType> <accessToken>
Accept: application/json
```

JSON requests also set:

```http
Content-Type: application/json
```

Multipart upload and transcription requests set:

```http
Content-Type: multipart/form-data; boundary=<generated-boundary>
```

## Models

```http
GET /v1/models
Authorization: Bearer <access-token>
Accept: application/json
```

Consumed response shape:

```json
{
  "data": [
    { "id": "grok-4.3" }
  ]
}
```

The CLI maps `data[].id` to selectable model IDs.

Model resolution in OAuth mode:

- Exact model IDs returned by `/v1/models` win.
- `fast`, `non-reasoning`, and `quick` prefer the first model containing `non-reasoning`, then fall back to `grok-4.3`.
- `auto`, `expert`, `reasoning`, `think`, and `heavy` prefer the first model containing `reasoning` but not `non-reasoning`, then fall back to `grok-4.3`.
- Grok 4.3 aliases such as `grok-4.3-beta`, `grok-420`, `43`, and `beta` resolve to `grok-4.3` when available.
- The default OAuth model is `grok-4.3`, else the first returned model, else `grok-4.3`.

## Responses

Non-streaming messages use:

```http
POST /v1/responses
Authorization: Bearer <access-token>
Accept: application/json
Content-Type: application/json
```

Request body:

```json
{
  "model": "grok-4.3",
  "input": [
    {
      "role": "user",
      "content": "Hello"
    }
  ],
  "store": true
}
```

Optional fields:

- `previous_response_id`: sent when continuing a stored OAuth thread.
- `max_output_tokens`: used by the tiny verification response.
- `stream`: set to `true` only when CLI streaming is enabled.

With file attachments, `content` becomes an array:

```json
[
  { "type": "input_text", "text": "Summarize this file" },
  { "type": "input_file", "file_id": "file-123" }
]
```

Consumed non-streaming response fields:

- Required response ID: `id`.
- Text from `output_text`, falling back to `output[].text`, then `output[].content[].text`.

## Responses Streaming

When the CLI is in streaming mode, OAuth messages call the same endpoint with `stream: true`:

```json
{
  "model": "grok-4.3",
  "input": [
    {
      "role": "user",
      "content": "Think through this problem"
    }
  ],
  "store": true,
  "stream": true
}
```

The response is parsed as server-sent events. Supported event shapes:

```text
event: response.created
data: {"type":"response.created","response":{"id":"resp_..."}}
event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","delta":"reasoning summary"}
data: {"type":"response.output_text.delta","delta":"answer token"}
data: {"type":"response.completed","response":{"id":"resp_...","output_text":"final answer"}}
data: [DONE]
```

Mapping into CLI stream events:

- `response.reasoning_summary_text.delta` becomes `ConversationResponse(isThinking: true)`.
- `response.output_text.delta` becomes a normal answer delta.
- `response.completed` or `[DONE]` finalizes the response.
- `response.failed` and `response.error` surface as API errors.
- SSE control lines such as `event:`, `id:`, `retry:`, and `:` comments are ignored.

The parser also accepts OpenAI-style `chat.completion.chunk` content and `reasoning_content` deltas as a defensive fallback, but `/v1/responses` is the primary transport.

## Files

Upload:

```http
POST /v1/files
Authorization: Bearer <access-token>
Accept: application/json
Content-Type: multipart/form-data; boundary=<boundary>
```

Multipart fields:

- `purpose=assistants`
- file field name: `file`

Consumed upload response fields:

- `id`
- `filename` or `fileName`
- `mime_type` or `mimeType`

List:

```http
GET /v1/files?limit=<page-size>
Authorization: Bearer <access-token>
Accept: application/json
```

Consumed list response shape:

```json
{
  "data": [
    {
      "id": "file-123",
      "filename": "notes.txt",
      "mime_type": "text/plain"
    }
  ]
}
```

Delete:

```http
DELETE /v1/files/{fileID}
Authorization: Bearer <access-token>
Accept: application/json
```

The delete response is preserved as raw JSON and maps `id` into the returned asset.

## Speech To Text

OAuth mode uses xAI STT instead of the Grok web voice endpoint:

```http
POST /v1/stt
Authorization: Bearer <access-token>
Accept: application/json
Content-Type: multipart/form-data; boundary=<boundary>
```

Multipart fields:

- file field name: `file`
- file MIME type inferred from extension or audio format

Consumed response shape:

```json
{
  "text": "transcript"
}
```

The transcript must be non-empty. `--refinement-level` is parsed by the CLI but only applies to the web speech-to-text path, not OAuth `/v1/stt`.

## Supported CLI Surface

OAuth mode supports:

- `grok auth oauth`
- `grok models`
- `grok message`
- Interactive chat
- `grok files list`
- `grok files upload`
- `grok files delete`
- `grok transcribe`

Web-only resources and account counters are not available in OAuth mode. Those commands fail before making web requests and tell the user to set `GROK_AUTH_MODE=web` when needed.

## Known Limitations

- OAuth mode does not expose Grok web rate-limit counters.
- OAuth auth failures do not trigger browser-cookie refresh.
- Stored OAuth conversation continuity depends on `previous_response_id` and xAI's Responses API storage.
- File delete path encoding currently uses the implementation's URL path encoding behavior.
- Streaming exposes summarized reasoning deltas when xAI emits them; it does not expose private internal chain-of-thought.

## References

- xAI Responses API overview: https://docs.x.ai/developers/model-capabilities/text/generate-text
- xAI streaming guide: https://docs.x.ai/developers/model-capabilities/text/streaming
- xAI reasoning guide: https://docs.x.ai/developers/model-capabilities/text/reasoning
- xAI files guide: https://docs.x.ai/developers/model-capabilities/files/chat-with-files
