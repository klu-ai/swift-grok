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

Useful options:

```bash
grok --reasoning solve this step by step
grok --deep-search latest Swift server ecosystem news
grok --no-search summarize this without live web data
grok --markdown write a checklist for release testing
grok --raw show me the source Markdown
grok --format raw show me the source Markdown
grok --stream draft the answer as it arrives
grok --no-custom-instructions ignore my saved custom instructions
grok --private ask without saving the conversation
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

The `grok agents` command group manages Grok's four server-side agent personalities.

List current customizations. If the account has no saved customizations, the CLI shows the built-in IDs:

```bash
grok agents
grok agents list
```

Set one agent's display name and instructions:

```bash
grok agents set 1 --name "Grok II" --instructions "Offer the skeptical read."
grok agents set 0 --instructions "Answer briefly and directly."
grok agents sync-custom
```

Agent `0` is always named `Grok` and uses the old custom-instructions role. The CLI fetches current settings before updating one agent so the other agent personalities are preserved.

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

Interactive chat commands:

```text
/new
/help
/list
/reason
/search
/realtime
/model expert
/format raw
/raw on
/private
/stream
/custom-instructions
/edit-instructions
/reset-instructions
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

`/personality` remains as a deprecated Grok 3 compatibility command and now points users to custom instructions instead.

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
