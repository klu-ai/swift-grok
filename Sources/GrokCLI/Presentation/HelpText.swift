import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    static func showHelp() {
        print("""

         ██████╗ ██████╗  ██████╗ ██╗  ██╗
        ██╔════╝ ██╔══██╗██╔═══██╗██║ ██╔╝
        ██║  ███╗██████╔╝██║   ██║█████╔╝
        ██║   ██║██╔══██╗██║   ██║██╔═██╗
        ╚██████╔╝██║  ██║╚██████╔╝██║  ██╗
         ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝

        Grok 4 up in your terminal

        Usage: grok [command] [options]

        Running just 'grok' with no commands starts an interactive chat session.

        Commands:
          chat              - Start an interactive chat session
          message <text>    - Send a message to Grok and exit
          transcribe <file>  - Transcribe audio and print the text
          auth              - Authentication commands
          list              - List and manage saved conversations
          models            - Show available Grok web modes
          agents            - Manage Grok agent settings
          tasks             - List, create, and archive Grok tasks
          skills            - List Grok skills and your enabled skills
          workspaces        - List, create, inspect, and delete Grok workspaces
          files             - Upload, list, and delete Grok assets
          help              - Show help information

        App Options:
          --markdown, -m    - Use markdown formatting in output (default)
          --raw             - Show raw Markdown text in output
          --json            - Emit scriptable JSON output
          --format <md|raw|json> - Choose output format
          --debug           - Show debug information
          --private         - Enable private mode (conversations will not be saved)
          --stream          - Stream responses as they are generated
          --quiet           - Suppress UI/status output for scriptable raw text
          --audio <path|->  - Transcribe audio before sending a message
          --audio-format <format> - Required with audio stdin or unknown extensions
          --refinement-level <level> - Speech-to-text refinement level
          --model <mode>    - Use auto, fast, expert, grok-4.3-beta, heavy, or a raw modeId

        JSON Mode:
          - Every CLI command accepts --json, --format json, or --format=json
          - stdout is reserved for JSON; human progress and debug banners are suppressed
          - Use an initial message for JSON chat output
          - grok message --stream --json emits NDJSON, one event object per line

        Scriptable Text:
          - grok message --raw --quiet writes only assistant answer text to stdout
          - grok message reads piped stdin when no message args or prompt file are supplied
          - grok message --prompt-file <path> reads a UTF-8 prompt file
          - grok message --audio <path> transcribes audio, then sends the transcript
          - grok transcribe <path> prints only the transcript
          - grok chat --raw --quiet supports cleaner piped multi-message sessions

        Chat Commands:
          /new              - Start a new conversation
          /help             - Show interactive command help
          /list             - List and load past conversations
          /tasks            - List or manage tasks
          /agents           - List or manage agent settings
          /skills           - List Grok skills
          /workspaces       - List or manage workspaces
          /files            - List files/assets
          /auth             - Refresh browser credentials
          /auth help        - Show auth commands
          /agents help      - Show agent management usage
          /tasks help       - Show task command usage
          /skills help      - Show skills command usage
          /workspaces help  - Show workspace command usage
          /files help       - Show file command usage
          /workspace        - Choose the project for new chats
          /workspace select - Choose the project for new chats
          /attach           - Browse files and attach one to following messages
          /attach upload    - Upload a local file and attach it
          /attach clear     - Remove all attached files
          /audio <path>     - Transcribe audio, edit the text field, then send
          /audio-send <path> - Transcribe audio and send immediately
          /transcribe <path> - Transcribe audio and print text only
          /model <mode>     - Switch model for following messages
          /mode, /models    - Model command aliases
          models <mode>     - Common commands also work without the slash
          /format [md|raw]  - Toggle or choose Markdown/Raw output
          /md, /markdown    - Enable Markdown output
          /raw [on|off]     - Toggle raw Markdown output
          /private [on|off] - Toggle private mode (conversations not saved)
          /stream [on|off]  - Toggle streaming responses
          /reset-conversation - Clear the current conversation context
          /special          - Start a private special-mode conversation
          /clear            - Clear the current screen
          /cls              - Alias for /clear
          /exit, /quit      - Exit the app

        Notes:
          - In chat mode, conversation context is maintained between messages
          - Use '/new' to start a new conversation thread
          - Use 'exit' or '/exit' to exit the app
          - The message command always starts a new conversation without context
          - Reasoning is always enabled for all models; --reasoning and /reason are legacy no-ops

        Examples:
          grok                                      - Start interactive chat mode
          grok Hello                                - Start chat with initial message "Hello"
          grok message Hello, how are you today?    - Send a message and exit
          grok message --model expert Explain this  - Send a message using Expert
          cat prompt.md | grok message --raw --quiet - Send piped prompt text
          grok message --raw --quiet --prompt-file prompt.md
                                            - Send a prompt file and print answer text
          grok message --json Explain this briefly  - Send a message and print JSON
          grok message --stream --json Draft a note  - Stream NDJSON events
          grok message --audio note.webm --raw --quiet - Send an audio transcript
          grok transcribe note.webm                  - Print an audio transcript
          grok auth                                 - Generate new credentials from browser cookies
          grok auth generate --json                  - Generate credentials and print JSON
          grok auth import /path/to/credentials.json --json
                                                    - Import credentials and print JSON
          grok models                               - Show available web modes
          grok models --json                        - Show available web modes as JSON
          grok agents list                          - List built-in agent IDs
          grok agents show 0                        - Show full agent instructions
          grok agents edit 0                        - Edit agent instructions in $EDITOR
          grok agents set 0 --instructions "Answer briefly."
                                                    - Set agent 0 instructions
          grok tasks                                - List tasks
          grok tasks list --json                    - List tasks as JSON
          grok skills                               - List skills
          grok workspaces                           - List workspaces
          grok workspaces delete <workspaceId>      - Delete a workspace
          grok files list                           - List recent assets
          grok files delete <fileId>                 - Delete an asset
          grok list                                 - List and select from saved conversations
          grok list --json                          - List conversations as JSON
        """.green.bold)
    }

    static func printHelpJSON() throws {
        try printJSONResult(
            command: "help",
            category: "help",
            data: AnyCodable([
                "usage": "grok [command] [options]",
                "commands": [
                    "chat",
                    "message",
                    "transcribe",
                    "auth",
                    "list",
                    "models",
                    "modes",
                    "agents",
                    "tasks",
                    "skills",
                    "workspaces",
                    "workspace",
                    "files",
                    "test",
                    "help"
                ],
                "jsonOptions": ["--json", "--format json", "--format=json"],
                "streaming": "grok message --stream --json emits NDJSON"
            ])
        )
    }


}
