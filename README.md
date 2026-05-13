# SwiftGrok

SwiftGrok provides a Swift `GrokClient` library, an OpenAI-compatible proxy, and a terminal CLI named `grok`.

The CLI is designed for quick shell use. Bare text starts chat with an initial message:

```bash
grok how tall is the moon
```

## Requirements

- macOS 14 or newer for the CLI
- Swift 6 toolchain
- Python 3 for browser-based authentication
- A browser session logged in to [grok.com](https://grok.com)

## Install The CLI

From a checkout:

```bash
git clone https://github.com/klu-ai/swift-grok.git
cd swift-grok
Scripts/install_cli.sh
```

The installer builds the release `grok` product and copies:

- `grok` to `/usr/local/bin` when writable, otherwise `~/.local/bin`
- `cookie_extractor.py` beside the binary so `grok auth` can find it

Choose a specific install location when needed:

```bash
Scripts/install_cli.sh --user
Scripts/install_cli.sh --system
Scripts/install_cli.sh --bin-dir "$HOME/bin"
Scripts/install_cli.sh --prefix /opt/swift-grok
```

If the install directory is not on `PATH`, add it to your shell profile:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
exec zsh
```

## Authenticate

Log in to [grok.com](https://grok.com) in your browser, then run:

```bash
grok auth
```

`grok auth` generates credentials from browser cookies. You can also target a browser directly:

```bash
grok auth safari
grok auth chrome
grok auth auto
```

Browser shortcuts are `auto`, `safari`, `atlas`, `chrome`, `firefox`, `chromium`, `brave`, `edge`, and `arc`.

You can also import an existing JSON credential export:

```bash
grok auth import /path/to/credentials.json
```

## Basic Usage

Start chat with an initial message:

```bash
grok how tall is the moon
```

The prompt stays open after Grok answers. Use `grok message` when you want one response and then an exit.

Start interactive chat:

```bash
grok
```

Send one message and exit:

```bash
grok message explain Swift actors in one paragraph
```

Use stdin or a prompt file for longer prompts:

```bash
cat prompt.md | grok message --raw --quiet
grok message --raw --quiet --prompt-file prompt.md
```

Useful options:

```bash
grok --markdown write a checklist for release testing
grok --raw show me the source Markdown
grok --format raw show me the source Markdown
grok --stream draft the answer as it arrives
grok message --raw --quiet print only the answer text
grok --private ask without saving the conversation
```

Reasoning is always enabled for all models, including `fast`. The old `--reasoning`, `/reason`, and `/reasoning` controls are accepted as legacy no-ops.
Search is automatic in Grok 4 and has no CLI toggle.
Instructions are configured in Grok agent settings, not through a separate local custom-instructions toggle.

Human mode may print status text and terminal UI on stdout. JSON mode reserves stdout for JSON. For scriptable plain text, use `grok message --raw --quiet`; progress, warnings, debug output, and errors are kept off stdout.

`grok message` uses exactly one prompt source: inline message arguments, `--prompt-file <path>`, or stdin. If no inline message or prompt file is supplied and stdin is piped, stdin is used automatically. `--stdin` is also available when you want to make that choice explicit.

## Audio And Transcription

Use `--audio` when the prompt should come from a local audio file:

```bash
grok message --audio recording.webm
grok message --audio recording.webm --audio-format webm
grok chat --audio recording.webm
```

In non-interactive commands, audio is transcribed first and the transcript is then automatically sent to Grok as the message. Use `grok transcribe` when you only want the transcript and do not want to create or continue a chat:

```bash
grok transcribe recording.webm
grok transcribe recording.webm --json
```

`--audio` is mutually exclusive with inline message text, `--stdin`, and `--prompt-file`. To read binary audio from stdin, pass `--audio -` and provide `--audio-format` because there is no filename extension to inspect:

```bash
cat recording.webm | grok message --audio - --audio-format webm
cat recording.webm | grok transcribe - --audio-format webm
```

Supported audio formats are inferred from common extensions such as `webm`, `wav`, `mp3`, `m4a`, `ogg`, and `flac`. If inference fails, pass `--audio-format`.

Interactive chat supports audio slash commands:

```text
/audio recording.webm
/audio-send recording.webm
/transcribe recording.webm
```

`/audio` transcribes and pre-fills the editable prompt so you can revise it before sending. `/audio-send` transcribes and sends immediately. `/transcribe` prints the transcript without sending it.

Swift callers can use the speech-to-text helpers directly:

```swift
let client = try GrokClient(cookies: cookies)

let fileTranscript = try await client.speechToText(
    at: "/path/to/recording.webm"
).text

let dataTranscript = try await client.speechToText(
    audioData: audioData,
    audioFormat: "webm"
).text

let base64Transcript = try await client.speechToText(
    audioBase64: audioData.base64EncodedString(),
    audioFormat: "webm",
    refinementLevel: GrokClient.defaultSpeechRefinementLevel
).text
```

## JSON Output

JSON mode reserves stdout for machine-readable JSON. Human progress/status banners are suppressed so stdout can be piped safely to tools such as `jq`; the `--debug` flag is reflected in result metadata instead of human debug lines.

Every CLI command accepts `--json`, `--format json`, or `--format=json`:

```bash
grok message --json "summarize Swift actors in two bullets"
grok message --format json --model expert "explain AsyncSequence"
grok chat --format=json "explain AsyncSequence"
grok models --json
grok models --format json
grok tasks list --format json
grok tasks create --prompt "Check this tomorrow" --name "Follow up" --json
grok list --json
grok list --conversation <conversationId> --json
grok auth generate --json
grok auth import /path/to/credentials.json --json
grok help --json
```

Non-streaming JSON commands print one JSON result object. Streaming message JSON prints newline-delimited JSON (NDJSON), one event object per line:

```bash
grok message --stream --json "draft a short release note" | jq -c '.'
```

The streamed events include request, trace, assistant delta, and final assistant response records.

Authentication commands support JSON for generate/import results and can still consume credential JSON:

```bash
grok auth
grok auth chrome --json
grok auth import /path/to/credentials.json --json
```

## Models And Modes

Show available modes:

```bash
grok models
```

Use a mode for one command:

```bash
grok --model expert explain this code path
grok --model fast summarize this file
grok --mode heavy review this design
grok --model grok-4.3-beta compare these approaches
```

In interactive chat, switch modes with:

```text
/model expert
models Expert
model 4
```

Known aliases include `auto`, `fast`, `expert`, `grok-4.3-beta`, and `heavy`. You can also pass a raw Grok web mode ID.

## Agents

The `grok agents` command group manages Grok's server-side agent settings. Basic accounts usually expose one agent; SuperGrok accounts can expose four customizable agents.

List current customizations:

```bash
grok agents
grok agents list
```

Set one agent's display name and instructions:

```bash
grok agents show 1
grok agents edit 1
grok agents set 1 --name "Grok II" --instructions "Offer the skeptical read."
grok agents set 0 --instructions "Answer briefly and directly."
```

The CLI fetches current settings before showing or updating one agent, then posts the full agent settings payload back so the other agent settings are preserved.

## Workspaces, Tasks, Skills, And Files

List and create workspaces:

```bash
grok workspaces list
grok workspaces create --name "Research" --model expert
grok workspaces add-conversation <workspaceId> <conversationId>
grok workspaces delete <workspaceId>
```

List and create tasks:

```bash
grok tasks list
grok tasks create --prompt "Check this tomorrow" --name "Follow up"
grok tasks archive <taskId>
```

List available and enabled skills:

```bash
grok skills list
grok skills mine
```

Upload and list files/assets:

```bash
grok files upload ./notes.pdf
grok files list
```

In interactive chat, the same areas are available with `/workspaces`, `/tasks`, `/skills`, and `/files`.

## Conversations

List and resume saved conversations:

```bash
grok list
```

Inside interactive chat, `/list` loads the selected conversation. The next message continues that conversation using the loaded parent response.

For a cleaner piped multi-message session, use raw quiet chat:

```bash
printf 'first prompt\nsecond prompt\n/quit\n' | grok chat --raw --quiet
```

Interactive chat commands:

```text
/new
/help
/list
/model expert
/format raw
/raw on
/private
/stream
/auth
/agents
/tasks
/skills
/workspaces
/workspace
/files
/attach
/quit
```

In interactive chat, `/agents`, `/tasks`, `/skills`, `/workspaces`, and `/files` list by default. `/workspace`, `/attach`, and `/model` open pickers. Slash command groups are preferred for command-style input; unknown slash commands show an error, while unknown bare text is sent as chat.

## Swift Package Usage

Add the library to another Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/klu-ai/swift-grok", from: "1.0.0")
]
```

Then depend on `GrokClient` from your target.

## Proxy

The `proxy` executable exposes an OpenAI-compatible API backed by Grok. See [PROXY_README.md](PROXY_README.md) for local setup and [DOCKER.md](DOCKER.md) for Docker-based setup.

## Troubleshooting

- `grok: command not found`: add the installer directory, usually `/usr/local/bin` or `~/.local/bin`, to `PATH`.
- `Could not find cookie_extractor.py`: reinstall with `Scripts/install_cli.sh`; the helper should sit beside the `grok` binary.
- Authentication errors: the CLI will tell you when saved cookies are rejected and will try to refresh them from your browser automatically. You can also run `/auth` inside interactive chat or `grok auth` from your shell.
- Browser extraction fails: confirm Python 3 is installed and the browser is closed if its cookie store is locked.
- Build fails: run `swift --version` and confirm Swift 6 is active.
- Need more detail: add `--debug` to the command.

## Project Layout

- `Sources/GrokClient/`: Swift client library and API models
- `Sources/GrokCLI/`: `grok` command-line interface
- `Sources/GrokProxy/`: OpenAI-compatible proxy server
- `Scripts/`: installer and browser authentication helper
- `Tests/`: package tests

## License

SwiftGrok is released under the MIT License. See [LICENSE](LICENSE) for details.
