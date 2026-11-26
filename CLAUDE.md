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
- `python3 -I scripts/find_eyes.py <glb> <preview.png> [dark]` finds eye positions for sleeper eyelids (`src/shared/Faces.luau`); `dark` for glossy black eyes. Never pass a `thumb.png` as the preview path (it overwrites it).
- `python3 -I scripts/render_portrait.py <glb> <Name> [--preview out.png]` bakes a 160 px RGBA portrait into `src/shared/PortraitData/` for the Index and reveal card (`src/shared/Portraits.luau`).
- **Client mesh limit:** a client can hold only ~8 EditableMeshes at once, whatever their size (measured 2026-11-26; destroying the EditableMesh blanks its MeshPart). `MeshLoader` is a ref-counted pool capped at 7: call `MeshLoader.release(name)` (or `CreatureView.destroy`) for every `get`; decorative props pass `{ optional = true }`. CreatureView only builds sleepers in the player's wing; props load only in the Food Court. Screens use portraits, not viewports. Each new wing adds meshes, so the lasting fix is importing the models as uploaded assets (owner's call).

## Layout

- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client
- `src/shared` → ReplicatedStorage.Shared
- `default.project.json` → the mapping above plus Lighting.Technology; the map is built by `src/server/Map.luau` at runtime
- Tuning (noise, speeds, pickup window, prices, upgrade tracks, evolutions) lives in `src/shared/Config.luau` → `Tuning`; wings (price, coin and wake multipliers, families) in `Config.Wings`
- Look: `src/shared/Theme.luau` (Builder Sans, light palette, cards, floating place labels). Use it for every new UI and world label.
- Wings: the Arcade (east wall) and Toy Barn (west wall, Z 128..152) are behind paid glass gates (`wingGate` in Map); unlocked characters are put in collision group `Pass_<wing>` (wings unlock in order, so the deepest pass opens every earlier gate). Wing data lives in `Config.Wings` (price, coin/wake/quest multipliers, families, icon, `Bounds`); use `Config.wingAt(pos)` instead of hard-coded coordinates.
- Events (B3): `src/server/Events.luau`. Snack Rush every 15 min UTC-aligned (2 min, one wing open to someone in the server): creatures grabbed there bank with `RushWeight` forms (Glazed/Jumbo) and respawn in 2 s. Wanted posters: one creature per wing per UTC hour (seeded by hour, so servers agree; "Any" or "Fancy" = Glazed or better) pays 3x (`Config.isWanted`). Published as workspace attributes (`RushWing/RushUntil/RushNextAt`, `WantedSpecies_<wing>/WantedForm_<wing>/WantedUntil`). Debug: `rush <wing> <seconds>` (nil ends), `wanted <species> Any|Fancy` (nil resets).
- Nudge (B3): other players' carriers get a client-side `NudgePrompt` (F / tap, `src/client/Nudge.luau`); the server (`tryNudge` in Main) checks range, your 5 s cooldown, the target's 2.5 s cooldown, the hideout safe zone (`Map.inHideout`) and the newbie shield (`NudgeShield` attribute, < 3 rescues), then `Sleepers.nudge` adds `Tuning.Nudge.Wake`. Solo test: debug `nudge <name> <skipCooldowns>` nudges yourself; the real prompt needs two clients.
- Overtime (B4 rebirth): `PlayerData.clockIn` (needs the Toy Barn and `Config.overtimeCost(n)` coins; resets coins, jar, Sneakers, Steady Hands; +1 overtime, +1 token) and `buyPerk` (HeadStart, SteadyStart, LuckyPaws, BigJar, AutoCollect; next level costs level+1 tokens). `Config.coinMult(p)` (+25% per Overtime) applies to rescue coins and shelf income. Leaderstats has an Overtime column. Debug: `clockin`, `perk <name> <id>`.
- Toy Barn: squeaky aisle (`Squeak` zones: a spike on stepping onto a toy, then loud) and Plush Mountain (Shelter, route `PlushPile`, Squeakicorn evolution). Each wing has its own rare stage/timer (`RareAt_<wing>` / `RareActive_<wing>` workspace attributes). Route zones carry a `Route` attribute (Vent, BallPit) that evolutions check.
- Plan and milestones: `docs/roadmap.md`
- Shelves (B2): `PlayerData` keeps `slots`, `display` (one `{s, f}` per slot, `{}` = empty), `jar` and `lastSeen`. The server ticks income into the jar every 2 s (`Config.displayRate`, `Tuning.Display`); offline time (capped) is added on join for real saves only. Clients draw their own shelves (`src/client/Shelves.luau`, portraits on SurfaceGuis), so every player sees their own displays in the shared hideout. Debug: `jar <name> <amount> <minutesAgo>`, `autofill`, `display`, `collect`.
- Daily quests + login streak (B2): `src/server/Quests.luau`. Quests roll per player per UTC day (seeded by UserId + day; one per tier from `Tuning.Quests.Pool`), progress from `Quests.onBank` (route tags Cozy/Vent/BallPit, `maxWake`, `regrabbed`, form, rarity) and jar collects, and are claimed with buttons. Reward maths lives in Config (`questReward`, `questBonus`, `streakPreview`, `streakReward`) so the HUD shows what the server pays. Debug: `quests <name> reroll|fill|streak <daysAgo>`, `claimquest`, `claimstreak`.
- Index page rewards (B2): `Tuning.IndexRewards` per wing (Found / Glazed / Jumbo tiers, coins + some trails), `Config.pageProgress`. `PlayerData.claimPage` / `equipTrail`; owned trails are derived from claimed pages (not saved separately); the server draws the equipped trail on the character (`Main.server.luau` `applyTrail`). Debug: `giveform`, `claimpage`, `trail`.

## Saving

- `src/server/Persistence.luau`: one DataStore record per player (`BrainrotProfiles_v1`, key `u_<UserId>`) with a session lock (`{job, t}`, 5 min timeout). Loads retry while another server holds a fresh lock, then take over; saves refuse to write if another server owns the lock.
- `src/server/PlayerData.luau`: `join` (load + sanitize), autosave every 60 s when dirty, `saveSoon` after purchases/new species/evolution/rares, `leave` (final save + release), `BindToClose` waits for writes.
- Studio uses a separate `BrainrotProfiles_v1_Studio` store. It needs Experience Settings > Security > "Enable Studio Access to API Services" (File menu in the new Studio UI). Without it the game runs session-only and the HUD says "progress is not saving".
- A failed load means that session never saves, so an outage can't overwrite good data.
- Changing the profile shape: bump `SCHEMA` in Persistence and handle old records in `PlayerData.sanitize`. (B1 added `tracks`, `wings`, `evo` without a bump: sanitize defaults them and migrates the old `ventRescues`.)
- StudioMCP's `character_navigation` pathfinding won't route through the wing gate; in playtests cross it with `face()` + `hold('W', s)`.
