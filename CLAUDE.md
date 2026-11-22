# roblox-game

Roblox game written as Luau files and synced into Roblox Studio with Rojo.

## Design reference

`docs/whitepaper.md` is the owner's design white paper. Build the five loops it describes (core, progression, collection, excitement, retention) into an original game: do not copy the analysed game's name, creatures, art or map.

## Dependency rules (set by the owner, 2026-11-21)

- Every external download (tools, plugins, Luau packages, anything) must be listed in `tools.lock.json` with an exact version, publish date, URL, size and SHA-256.
- Only versions published more than 7 days ago. `scripts/fetch_tools.py` enforces this and the checksum.
- Ask the owner before adding any new dependency. Prefer writing the code over adding a package.
- Nothing is installed system-wide or user-wide. Tools live in `tools/` (git-ignored) and are restored with the fetch script.
- No Roblox free models, toolbox assets or third-party Studio plugins other than the locked Rojo plugin: they can carry scripts.
- No secrets in the repo. Roblox API keys, if ever used, stay out of git.

## Commands

- Restore tools: `python3 -I scripts/fetch_tools.py`
- Build place file: `tools/rojo/rojo build -o build/roblox-game.rbxl`
- Live sync to Studio: `tools/rojo/rojo serve` (listens on localhost only; do not pass `--address`)

## Studio MCP + Meshy (project-scoped, added 2026-11-21)

- `.claude.json` local scope for this repo holds two MCP servers: `meshy` (pinned @meshy-ai/meshy-mcp-server@0.6.12, copied from brawler) and `roblox-studio` (Roblox's own `StudioMCP` binary inside RobloxStudio.app; nothing downloaded). Studio side: Assistant > ... > Manage MCP Servers > "Enable Studio as MCP server".
- `scripts/studio_mcp.py` talks to StudioMCP over stdio (`list`, `call <tool> '<json>'`, `luau execute_luau <file> Edit|Server|Client`).
- `scripts/sync_to_studio.py [--only Name]` pushes src/ into the open place via execute_luau (fallback when Rojo isn't connected). Studio caps Script.Source at ~200k chars, hence chunked MeshData.
- `scripts/playtest.py <scenario.py>` drives real input (character_navigation, keyboard, mouse) plus the Studio-only debug bridges `ServerStorage.BrainrotDebug` / `ReplicatedStorage.BrainrotClientDebug`.
- Don't use StudioMCP's generate_*/upload_*/insert_asset/open_cloud_invoke tools: they publish to Roblox.
- `scripts/mcp_bridge.sh "<allowed tools>" "<prompt>"` runs a headless Claude here so a session that started elsewhere can still call Meshy.

## Art pipeline

- Meshy sources: `art/meshy/` (concepts, `models/<name>/model.glb`, `ledger.json` with task ids and credits, `STYLE.md`).
- `python3 -I scripts/mesh_to_luau.py <glb> <Name> --tex 256` bakes a GLB into `src/shared/MeshData/<Name>.luau` (+ `_n` chunks). The client rebuilds it with EditableMesh/EditableImage (`src/shared/MeshLoader.luau`), so nothing is uploaded to Roblox.
- `python3 -I scripts/find_eyes.py <glb> <preview.png>` finds eye positions for sleeper eyelids (`src/shared/Faces.luau`).

## Layout

- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client
- `src/shared` → ReplicatedStorage.Shared
- `default.project.json` → the mapping above plus Lighting.Technology; the map is built by `src/server/Map.luau` at runtime
- Tuning (noise, speeds, pickup window, prices) lives in `src/shared/Config.luau` → `Tuning`
