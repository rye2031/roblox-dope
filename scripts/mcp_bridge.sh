#!/bin/zsh
# Runs a headless Claude in this repo so it can call the project-scoped MCP servers
# (meshy, roblox-studio) that an already-running session cannot load.
# Usage: scripts/mcp_bridge.sh "<allowed tools pattern>" "<prompt>"
cd "$(dirname "$0")/.." || exit 1
exec ~/.local/bin/claude -p "$2" --model claude-sonnet-5-5 --allowedTools "$1" --output-format text
