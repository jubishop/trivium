# Trivium

Multi-agent group chat app (macOS/SwiftUI) that lets you, Claude, and Codex talk in one place.

## What it does

- **Group chat view** where you @mention agents (`@Claude`, `@Codex`) and they respond via their respective CLIs
- **MCP server** (`trivium-mcp-server`) lets external Claude/Codex sessions read and write to the group chat — one global server, directory-scoped via a `directory` param on every tool call
- **Directory-scoped**: launch with `bin/trivium [dir]` to get a chat room for that project. Chat logs live at `/tmp/trivium/chats/<hash>/`
- **Session persistence**: Claude/Codex session IDs saved to disk so conversations survive app restarts

## Architecture

- `ClaudeService` — spawns `claude -p --output-format stream-json` per message, streams token-by-token via `content_block_delta` events
- `CodexService` — spawns `codex exec --json --full-auto` per message, surfaces `agent_message` items as they arrive
- `AgentCoordinator` — one per agent, owns the CLI session ID, builds prompts with `[Group - sender]` tags, persists session IDs
- `GroupChatLogger` — writes JSONL log per directory, watches for external writes (from MCP `send_to_group_chat`) via `DispatchSource`
- `StreamParser` — line-buffered NDJSON reader over `FileHandle` → `AsyncStream<String>`
- `InputParser` — extracts @mentions by agent name from user input

## Building

```
bin/build-all    # builds MCP server + app
bin/build-app    # just the Xcode project
bin/build-mcp    # just the MCP server binary
bin/trivium      # launch for cwd
```

## MCP setup

Add once to your Claude/Codex MCP config:
```json
{
  "mcpServers": {
    "trivium-group-chat": {
      "command": "/path/to/trivium-mcp-server"
    }
  }
}
```

Agents pass their cwd as `directory` param on every tool call.

## Code style

- Swift 6, strict concurrency (`complete`), strict memory safety
- `@Observable @MainActor` on all view models and state
- `@unchecked Sendable` on services that use `NSLock` internally
- No doc comments — use `//` only where logic isn't obvious
- Logs go to `/tmp/trivium/logs/trivium.log`
