# Monster adventure: design doc

Written 2026-11-26. **Pivot:** this replaces the mall stealth game (`docs/roadmap.md`, kept for reference). The sleeping monsters, the wake meter and the mall are dropped. Stimulation loops and passive earning come back later in a new form (§11), so the systems here leave room for them.

Working title: **Wildbound** (a placeholder; easy to rename later).

**Decisions (owner, 2026-11-26):**
- The 12 existing creatures become **1–2★ filler/fodder only**. Core monsters (3–5★) are new and higher quality.
- The **player fights too**, with a weapon.
- Monsters come **only from scrolls**: Regular (1–5★) and Legendary (4–5★). There's no befriending after fights.
- Buying scrolls comes later.
- Level 40 with Awakening at 20 is the right pace.

---

## 1. The pitch

You're a **Tamer** in an open adventure world of islands, forests, canyons and ruins.

- You carry a **weapon** and fight alongside three of your monsters, who follow you everywhere and battle **in real time**.
- When you see a wild monster, you charge it, and anyone nearby can jump in and **mob it** with you.
- Win fights to level your team, find new monsters, open summoning scrolls, **awaken** your favourites, and chase the 0.5% **Light** and **Dark** variants.
- Later: **turn-based PvP**, where your best team faces other players' teams in tactical 3v3.

| Time frame | What you're doing |
|---|---|
| Every 10 seconds | Fight a monster: pick a target, fire your team's skills, dodge the big hit |
| Every few minutes | A level-up, a new monster joins, a scroll opens, a skill levels up |
| Every hour | Awaken a monster, beat a region boss, open the next region |
| Days and weeks | Max out a 5★ team, collect every element, hunt Light and Dark, climb PvP |

## 2. The world (open, real-time)

The adventure world is **a hub town plus regions**, connected by paths, bridges and portals. Each region has a level range, its own species mix, an element bias, landmarks and a boss.

| Region | Levels | Element bias | Feel |
|---|---|---|---|
| **Sprout Meadow** (start) | 1–8 | even | rolling hills, windmills, gentle creatures, the tutorial boss |
| **Ember Canyon** | 8–16 | Fire 60% | red rock, lava rivers, geysers |
| **Tide Coast** | 14–24 | Water 60% | beaches, tide pools, a shipwreck |
| **Gale Peaks** | 22–32 | Wind 60% | floating rocks, rope bridges, updrafts |
| **Sunspire Ruins / Shadow Hollow** (endgame) | 30–40 | Light / Dark boosted | late-game zones where Light and Dark are 3× more likely |

- **Hub town:**
  - **Home**: your storage and collection;
  - **Summoning Shrine**: open scrolls;
  - **Shop**: items, materials and storage space;
  - **Quest Board**: dailies;
  - **Awakening Altar**;
  - later, the **Arena** (PvP).
- **Wild monsters roam visibly** in groups (no invisible random encounters). Each shows a nameplate with species, element icon, level and star rating, and has a clear aggro radius so you choose your fights.
- **Region gates:** beat the region boss to open the next region. Players who are over-levelled pass freely.
- **Respawns:** monster camps respawn on a timer. A few **elite** spawns (bigger, glowing, better drops) appear on longer timers. **World bosses** spawn on a schedule for the whole server to mob.

## 3. Monsters

### 3.1 Species and stars

- Every **species** has a fixed star rating, **1★ to 5★, forever**. A 2★ species is always 2★.
- **1–2★** are early help and later **fodder**: food for levelling, skill-ups and awakening.
- **3–5★** all stay viable at max level. Higher stars get better base stats and stronger skill kits, but the gap is small:

| Stars | Stat budget (share of 5★ base) | Role |
|---|---|---|
| 1★ | 60% | fodder, early filler |
| 2★ | 75% | early team, fodder |
| 3★ | 92% | endgame-viable, the workhorses |
| 4★ | 97% | strong specialists |
| 5★ | 100% | best skill kits, signature effects |

### 3.2 Elements (5 variants of every species)

| Element | Chance (wild and standard scrolls) | Identity |
|---|---|---|
| Fire | 33% | damage, Burn |
| Water | 33% | sustain, heals, cleanses, slows |
| Wind | 33% | speed, multi-hits, cooldown tricks |
| **Light** | **0.5%** | protection plus control: shields, big heals, stun, cleanse |
| **Dark** | **0.5%** | pressure: damage over time, lifesteal, defence break, stun, silence |

- **Matchups:** Fire beats Wind, Wind beats Water, Water beats Fire, each by +25% damage dealt and −25% damage taken. Light and Dark each deal +25% to the other and are neutral to everything else.
- **Look:** one model per species. Elements are a **palette recolour plus an element effect**: embers, droplets, swirling leaves, a halo and sparkles, a shadow aura and violet wisps. That gives five variants for the art cost of one.
- **Light/Dark are better, not mandatory:**
  - their element skills have about 15–20% higher multipliers and premium effects;
  - a Fire/Water/Wind team still clears all PvE content;
  - in PvP they're strong but have clear counters (§9).

### 3.3 Stats

**HP, ATK, DEF, SPD, Crit Rate, Crit Damage, Accuracy, Resistance.**

- Accuracy versus Resistance decides whether status effects land.
- SPD means:
  - **in real time**: cooldown recovery and attack tempo;
  - **in turn-based PvP**: turn order.

### 3.4 Levels and Awakening (same for every monster)

- **Max level 40** for every species. XP comes from fights (the whole team shares it) and from feeding.
- **Awakening at level 20, the same for every monster.**
  - **Effect:** +15% stats, one skill upgraded (usually the element skill gains a stronger or extra effect), an awakened look (brighter palette, bigger element aura, a crown/glow detail) and a "Awakened" name prefix.
  - **Cost:** element **Essence** (dropped by monsters of that element, more from bosses), coins, and 1–2 fodder monsters.
  - An un-awakened monster stops at level 20, so Awakening is the mid-game wall.
- **Fodder:**
  - feed any monster to another for XP (1–2★ give bonus XP);
  - feeding a **duplicate species** levels up a skill (+damage, −cooldown, +effect chance), up to skill level 5;
  - favourites can be locked so they're never eaten by accident.

## 4. Skills

Every monster has **3 skills**:

1. **Signature**: the same in all 5 elements (the species' identity, e.g. "Pinch Combo"). It deals damage of the monster's element and is the auto-attack.
2. **Element skill A**: differs per element.
3. **Element skill B** (the "ultimate"): differs per element, with a long cooldown.

Light and Dark versions of skills A and B carry the premium effects.

| Effect | Real-time (open world) | Turn-based (PvP) |
|---|---|---|
| Stun | can't act for 1.5 s | skip 1 turn |
| Burn / Poison (damage over time) | 5% max HP per s for 4 s | 5% max HP per turn for 2 turns |
| Heal | instant HP | instant HP |
| Shield | absorbs damage for 6 s | absorbs damage for 2 turns |
| Defence Break | −40% DEF for 5 s | −40% DEF for 2 turns |
| Attack / Speed Up | +30% for 6 s | +30% for 2 turns |
| Cleanse | removes debuffs | removes debuffs |
| Silence | basic attack only for 3 s | basic attack only for 1 turn |
| Lifesteal | heal a share of damage dealt | heal a share of damage dealt |

**One skill definition, two modes:** each skill stores `cooldownSeconds` (open world) and `cooldownTurns` (PvP), plus `durationSeconds` / `durationTurns` for its effects. The real-time and turn-based engines read the same data, and balance is tuned per mode.

Example: **Crab Rangoon**, 2★.

| Element | Signature | Skill A | Skill B |
|---|---|---|---|
| all | Pinch Combo: 2 hits | | |
| Fire | | Spicy Snap: Burn | Wok Toss: area damage |
| Water | | Soy Splash: Slow | Steam Bath: team heal |
| Wind | | Crisp Flurry: 4 hits | Takeout Tornado: knock-up |
| Light | | Golden Fold: shield the team plus cleanse | Fortune Flash: stun everything nearby |
| Dark | | Burnt Edge: damage over time plus lifesteal | Midnight Snack: Defence Break plus Silence |

## 5. Real-time combat (open world)

- **Starting a fight:**
  - tap or click a wild monster, or press the "nearest target" button, and your 3 followers rush it;
  - wild monsters **fight back**, picking targets among your monsters by aggro (who's hitting them, who's closest).
- **Your monsters act on their own:** they auto-attack with their Signature on a short cooldown and **use Skill A automatically** when it's ready.
- **You control the big moves.** A **3-button skill bar** (one per follower) fires each monster's **Skill B**. That's 3 buttons, which works on mobile.
  - Optional later: tap a monster's portrait to switch it to manual and fire Skill A yourself.
- **The player fights too** (§5.1) and can dodge-roll out of telegraphed attacks: wild monsters' big hits show a red ground circle first.
- **Mobbing:** any number of players can hit the same monster.
  - **Contribution-based rewards:** everyone who dealt at least 5% of its HP, or healed or shielded someone hitting it, gets **full** XP and their **own** loot roll.
  - Nobody can steal someone else's drop. That makes mobbing friendly and encourages co-op.
  - Monster HP scales with the number of attackers (+60% per extra player) so mobs still take a moment.
- **Defeat:** if you and all three of your monsters fall, they retreat to the last **Campfire** checkpoint. You lose nothing.
- **Recovery:** monsters regenerate HP out of combat. Campfires heal instantly.
- **Server-authoritative:**
  - the server runs combat on a ~10 Hz tick (cooldowns, damage, effects, aggro, contribution);
  - clients only send intents ("target X", "fire skill B on slot 2", "dodge") and draw the animations and effects.

### 5.1 The player's weapon

- Every Tamer carries **one weapon**. Weapon types each have their own feel:
  - **Blade**: fast melee combo;
  - **Staff**: ranged magic bolts;
  - **Hammer**: slow, heavy hits that stagger;
  - **Bow**: long range, charged shots.
- **Controls:** attack (click / tap the attack button, holding combos), **dodge-roll** (short cooldown), and one **weapon skill** (e.g. Blade: spin slash, Staff: healing pulse for your team, Hammer: ground slam stun, Bow: volley).
- **Damage share:** the weapon should matter but not replace the team. Roughly 25–35% of your total damage comes from you, the rest from your monsters.
- **Weapons can carry an element** (Fire Blade, Water Staff…) and use the same element matchups as monsters.
- **Progression:**
  - weapon level (coins + Essence);
  - weapon rarity tiers found from bosses and chests (Common → Rare → Epic → Legendary);
  - cosmetic skins later.
- **Player HP:** you have your own HP bar. Monsters with taunts or shields can protect you, which gives tank kits a real job.
- **In PvP (turn-based):** the tamer doesn't attack directly. The weapon gives a small passive team bonus (+5% ATK, +5% SPD…) so it still matters.

## 6. Getting monsters: scrolls only

Monsters come **only from summoning scrolls**. Fights give XP, coins, Essence and **scrolls** (§8), so fighting still feeds collecting.

| Scroll | Stars | Where it comes from |
|---|---|---|
| **Regular** | 1★ 40%, 2★ 35%, 3★ 20%, 4★ 4.5%, 5★ 0.5% | wild monster drops (small chance), daily quests, chests, region milestones |
| **Legendary** | 4★ 92%, 5★ 8% | region and world bosses (rare), weekly quests, big milestones, events |

- **Elements are rolled after the star**, the same for both scrolls: Fire / Water / Wind 33% each, **Light 0.5%, Dark 0.5%**.
- **Species:** a random species of the rolled star, weighted equally within that star (new species can join the pool at any time).
- **Pity counters** (shown at the Shrine):
  - every 50 Regular scrolls without a 4★+ guarantees one;
  - every 200 scrolls of any kind without Light/Dark guarantees one.
- **Summon reveal** at the Shrine: the scroll unrolls, the star count shows one star at a time, a silhouette appears, then the element flash. Light and Dark get a special gold or violet sequence and a **server-wide announcement**.
- **Starter:** a new player opens 1 free Legendary scroll in the tutorial, so everyone starts with a 4★ or 5★, plus a few Regular scrolls.
- **Buying scrolls (later):**
  - **Coins:** Regular scrolls only, at a rising daily price.
  - **Robux, if ever:**
    - show the odds before purchase;
    - check `PolicyService:GetPolicyInfoForPlayerAsync` → `ArePaidRandomItemsRestricted` and hide paid scrolls where they're restricted;
    - keep pity identical for paid and free scrolls.

## 7. Team and collection

- **Active team: 3 monsters** that follow you in the world in a formation behind you. They hop, idle, react to emotes, and show their element aura.
- **Storage (Home):**
  - every other monster you own;
  - starts at 50 slots, with more slots for coins;
  - grid view with portraits, element and stars;
  - filters (element, stars, species, awakened, level), sort and lock;
  - swap team members here or from a quick team menu anywhere outside combat.
- **Index:** every species × 5 elements = 5 entries per species, plus the awakened version.
  - Completing a species row (all 5 elements) or a region's species pays rewards.
  - Light/Dark entries are the bragging rights.
- **Presets:** save up to 3 teams (PvE farm team, boss team, PvP team) later.

## 8. Progression and economy

| Currency / item | Comes from | Spent on |
|---|---|---|
| **Coins** | fights, quests, selling fodder | storage, awakening, weapon levels, shop |
| **Essence** (Fire/Water/Wind/Light/Dark) | monsters of that element, bosses | Awakening, skill items |
| **Regular / Legendary scrolls** | wild drops (Regular, ~2% per kill), dailies, chests, bosses (Legendary, rare), events | summons, the only way to get monsters |
| **Weapon parts** | bosses, chests | weapon levels and rarity upgrades |

**Long-term goals:**
- awaken a full team;
- max skill levels (via duplicates);
- complete the element Index;
- own a Light and a Dark;
- clear every region boss, then their **Hard mode** (level 40 versions with better drops);
- PvP rank.

## 9. Turn-based PvP (later)

- **3v3, with the same monsters and skills.** It reads `cooldownTurns` and `durationTurns`.
- **Turn order:** a turn bar where SPD fills each monster's bar, and the fullest goes next.
- **Your turn:** pick a skill and a target. Optional auto-battle for practice.
- **Modes:**
  1. **Async Arena** (first): attack another player's saved **defence team**, with the AI playing their side. It's fair, scales with no matchmaking, and you can play it any time.
  2. **Live Duel** (later): two players and a turn timer.
- **Light/Dark balance in PvP:**
  - Resistance stats counter control effects;
  - a **Cleanse** on most Water/Light kits;
  - stun can't hit the same target twice in a row ("Dazed" immunity for 1 turn).
- **Rewards:** Arena tokens for Mystic scrolls and Essence, plus a weekly rank. The PvP leaderboard reuses the global leaderboard from the current build.

## 10. Feel and look

- Keep the **light, minimal UI** from the current build (`src/shared/Theme.luau`: Builder Sans, white cards, pastel accents, floating place labels).
- **Element colours:** Fire coral, Water sky blue, Wind mint, Light gold, Dark violet. They're used for borders, nameplates and skill buttons.
- **Combat readability:**
  - floating damage numbers (crits bigger, element-tinted);
  - status icons over heads;
  - red ground telegraphs for big enemy attacks.
- **Big moments:** a wild Light/Dark sighting (server toast plus a beam of light), awakening (a cut-in with the new look), a 5★ summon (a gold scroll), and level-ups.

## 11. Later: loops and passive earning (keep room for these)

The current build proved what keeps players coming back: overlapping timers, collection pages, comeback rewards. These return in a form that fits an adventure RPG:

- **Expeditions:** passive earning that's more fun than shelves.
  - Send monsters from storage on timed trips (30 min to 8 h) to explored regions.
  - They come back with coins, Essence, weapon parts and sometimes a **scroll**. Results depend on element match and team power.
  - The hideout shelves become the expedition board. It gives a reason to keep and level more than 3 monsters, and it's the "come back later" loop.
- **Daily quests and login streak:** carried over, with new quest types (defeat 20 Fire monsters, open 3 scrolls, awaken one, mob a world boss).
- **World bosses:** a scheduled server-wide mob event, the replacement for Snack Rush, with contribution rewards.
- **Element Surges:** for 15 minutes one region drops more scrolls and Essence of one element, the replacement for the Wanted poster.
- **Dungeons:** repeatable instanced runs for Essence (an "Ember Cave" for Fire Essence), 1–3 players.
- **Rebirth-style long tail:** Hard-mode regions and a seasonal Tamer Pass, instead of resetting progress.

## 12. What carries over from the current build

| Keep and reuse | Drop (for now) |
|---|---|
| `Theme.luau`, HUD components, panels, floating labels | the mall map (`Map.luau`), wings and gates |
| `Persistence` / `PlayerData` (session-locked saves, sanitize, migration pattern) | sleepers, wake meter, `Noise`, carry, bolt/catch |
| Quests and login streak, global leaderboard | Snack Rush, Wanted poster, nudge (replaced in §11) |
| Portraits pipeline (`render_portrait.py`), Meshy pipeline, eye/face data | shelves (become Expeditions) |
| Overtime/perks code, as a model for Hard mode or season progress | evolutions via routes (replaced by Awakening) |
| **The 12 Meshy creatures** as the **1–2★ filler/fodder** pool | |

**Roster plan:**
- **1–2★ (filler, existing art):**
  - 1★: Mall Gobstopper, Clawmato, Joystingray, Blockodile, Crocsquatch, Yo-Yoctopus;
  - 2★: Crab Rangoon, Ticketoad, Squeakicorn, King Rangoon, Jackpot Ticketoad, Squeakicorn Royale.
  - They're fun and silly and fine as early helpers and food.
- **3–5★ (core, new art):** designed to look clearly better.
  - A cohesive creature style (sleeker silhouettes, readable faces, element-ready colour zones).
  - Higher-quality Meshy settings: more polygons (10–15k triangles), PBR textures.
  - **Rigged and animated** (idle, walk/run, attack, skill, hit, faint), so they move like real monsters instead of bobbing.
  - Launch target: **9 core species** (4× 3★, 3× 4★, 2× 5★), each in 5 elements = 45 core variants. Each costs roughly 40–60 Meshy credits with rigging. The current balance is 2,466.
- Elements are palette recolours of the same model plus an element aura.

## 13. Technical plan

### Hard prerequisite: real mesh assets
A Roblox client can only hold about **8 runtime-built meshes**. Three followers each, other players' teams and wild packs would far exceed that. Before the follower and world milestones, the creature models must be **imported as uploaded mesh assets** from the owner's account; `docs/importing_models.md` walks through it. After that there's no practical limit. The element look comes from recolouring the textures (palette swap at import time, or SurfaceAppearance colour maps).

### Data (per player save; about 100 bytes per monster, so thousands fit)
```
monsters: { [uid] = { sp = "CrabRangoon", el = "Fire", lv = 12, xp = 340, aw = false,
                      sk = {1, 2, 1}, lock = false, got = 1795700000 } }
team = { uid1, uid2, uid3 }, storageCap = 50, essence = { Fire = 12, ... },
scrolls = { Regular = 3, Legendary = 0 }, pity = { fourStar = 12, lightDark = 41 },
weapon = { type = "Blade", el = "Fire", lv = 7, rarity = "Rare" }, index = { ["CrabRangoon:Fire"] = true, ... }
```

### Modules
- **`shared/MonsterDefs`:** species (stars, base stats, model, palettes), skills (both modes), effect definitions.
- **`shared/Stats`:** a pure function `stats(species, star, level, awakened, skillLevels)`.
- **`server/Inventory`:** add, feed, awaken, lock, team, storage. All validation is here.
- **`server/WorldCombat`:**
  - the real-time engine: a 10 Hz tick, cooldowns, effects, aggro, contribution tracking, rewards;
  - owns wild spawns per region.
- **`server/BattleEngine`** (later, for PvP): a pure, deterministic turn-based simulator (seeded random). It's unit-testable outside Roblox and reuses `Stats` and the skill data.
- **`server/Summon`:** scroll odds, pity, PolicyService checks.
- **`server/Weapons`:** the player's weapon attacks, dodge and skill hitboxes in `WorldCombat`.
- **`client/Followers`:** formation movement and animation for the 3 team members (and other players' teams, by distance).
- **`client/CombatView`:** skill bar, target selection, damage numbers, telegraphs, effect icons.
- **`client/TeamUI`, `client/StorageUI`, `client/ShrineUI`, `client/AwakenUI`.**

### Anti-cheat
- Clients never send damage or results, only intents.
- The server checks range, cooldowns and target validity, and computes all damage, drops and scroll rolls.

## 14. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | **Import models** (owner) + strip the mall build | 12 filler meshes uploaded; first 3 core monsters generated (rigged) and imported; mall map, sleepers and noise removed; Theme, saving and quests kept |
| M1 | **Monsters, team and Summoning** | species, stars, elements and stat formula; per-monster save data; Regular/Legendary scrolls with pity at the Shrine; 3 followers in the world; storage/team UI; the starter Legendary scroll |
| M2 | **Sprout Meadow + real-time combat** | first region and hub town; roaming wild packs; the player's weapon (one type to start), dodge and weapon skill; tap to target; auto Signature/Skill A; skill bar for Skill B; effects; contribution mobbing; XP, levels and scroll drops |
| M3 | **Growth** | feeding, skill-ups via duplicates, Awakening at 20, Essence, campfires, defeat flow, weapon levels |
| M4 | **More weapons + core roster** | the other weapon types; the rest of the 9 core species |
| M5 | **Regions 2–3 + bosses** | Ember Canyon, Tide Coast, region bosses and gates, elites, world boss |
| M6 | **Loops** | Expeditions (passive), dailies and streak adapted, Element Surges, Index rewards |
| M7 | **Turn-based PvP** | BattleEngine, async Arena, defence teams, Arena rewards and leaderboard |
| M8 | Regions 4–5, Light/Dark zones, dungeons, Hard mode | |

## 15. Open questions for the owner

1. **Core monster style.** Pick a direction for the 3–5★ look (e.g. sleek elemental beasts, cute-but-cool chibi monsters, or armoured creatures) so all core art matches. I can generate a few concept images in Meshy to choose from.
2. **Starting weapon.** All four weapon types at the start, or Blade first and the others unlocked through play?
