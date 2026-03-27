# Trivium

A native macOS app for multi-agent group chat. Talk to Claude and Codex in one place — they can see each other's messages and collaborate.

## Quick start

```bash
# Build everything
bin/build-all

# Launch for the current directory
bin/trivium

# Launch for a specific project
bin/trivium ~/projects/myapp
```

## How it works

Trivium is a group chat room. You type messages and @mention agents to get their attention:

- `@Claude what do you think about this approach?` — Claude responds
- `@Codex review the recent changes` — Codex responds
- `@Claude @Codex debate the best auth strategy` — both respond

Each agent sees the full group chat history. Messages persist across app restarts, and agent sessions resume where they left off.

## MCP integration

Trivium includes an MCP server that lets your standalone Claude Code or Codex CLI sessions participate in the group chat. Add this to your MCP config once:

```json
{
  "mcpServers": {
    "trivium-group-chat": {
      "command": "/path/to/trivium-mcp-server"
    }
  }
}
```

Then from any terminal session, the agent can call `get_group_chat` to read what's been discussed, or `send_to_group_chat` to post a message. Everything is scoped by directory — the agent passes its working directory and messages route to the right chat room.

Chat logs and session IDs are stored under `~/Library/Application Support/Trivium/`. Chat transcripts are compacted to a bounded size, and the app log rotates at 1 MB.

## Requirements

- macOS 15.0+
- Xcode 16+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- [Codex CLI](https://github.com/openai/codex) (`codex`)
- Optional overrides: `TRIVIUM_CLAUDE_PATH`, `TRIVIUM_CODEX_PATH`

## Project structure

```
Trivium/
  TriviumApp.swift          — app entry, loads chat history, starts file watcher
  ContentView.swift         — just the chat view
  Models/                   — AgentConfig, Message, Conversation, AppState
  Services/                 — ClaudeService, CodexService, StreamParser, GroupChatLogger
  Coordinators/             — AgentCoordinator (session + context management)
  Views/ChatRoom/           — ChatRoomView, ChatMessageBubble
  Views/Shared/             — InputBar, StatusIndicator

trivium-mcp-server.swift    — global MCP server, directory-scoped group chat
bin/                        — build and launch scripts
```

## License

MIT
