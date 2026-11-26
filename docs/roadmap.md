# DON'T WAKE THE BRAINROT: game plan and roadmap

Written 2026-11-26 after the first outside playtest. Builds on `docs/whitepaper.md` (the five loops) and the playtest feedback:

> "Everything should be a lot easier to understand… fonts on places like the shop should match a minimalist look and float in the sky… you go too slow, maybe a speed system… the map's too small."

## 1. The pitch and the plot

**The Megamall opens at 9.** Every night, brainrot creatures wander in and fall asleep all over the mall: in the food court, under arcade cabinets, in the ball pit and on the cinema seats. You're a **Keeper**. You have a hideout behind the cardboard boxes, and before the morning crowd arrives you sneak creatures home without waking them.

- **Every 30 seconds:** spot a sleeper, grab it, and choose a route home. The quiet way is long and safe; the loud shortcut is fast and risky. Watch the wake meter.
- **Every 5 minutes:** a rare sleeper appears on a stage, you buy the next speed level, or you unlock a buddy ability.
- **Every hour:** you unlock the next wing of the mall and get a new set of creatures to fill in.
- **Every day:** come back for your display shelf earnings, daily quests and the rotating "Wanted" creature.
- **Long term:** finish every wing's index in every form, rebirth for permanent bonuses, and chase Secret sleepers.

The light morning look follows from the plot: sunlight through the glass roof, pastel shops with their shutters still down, and calm music. The tension comes from the creatures, not from darkness.

## 2. The mall: hub and wings

The hideout is home. Each **wing** is its own area with:

- a quiet route, a loud shortcut and one buddy-ability gate;
- its own creatures and rare stage;
- one gate you buy to get in.

Deeper wings pay more and wake faster.

| # | Wing | Unlock | Gimmick (loud / quiet / ability) | Creatures | Status |
|---|---|---|---|---|---|
| 1 | **Food Court** | free | rattling escalator / Cozy Corner / vent (Crab Rangoon) | Crab Rangoon, Crocsquatch, Mall Gobstopper → King Rangoon | built |
| 2 | **Arcade** | 300 coins | dance floor that thumps on the beat / ball pit / prize-counter evolution (Ticketoad) | Ticketoad, Joystingray, Clawmato → Jackpot Ticketoad | **this milestone** |
| 3 | Toy Barn | 2,500 | squeaky-toy aisles / plush mountain / shelf climb (a jumpy buddy) | 3 + 1 evolution | next |
| 4 | Cinema | 12,000 | popcorn crunch floor / dark theatre where sleepers sleep deeper / projector booth | 3 + 1 | later |
| 5 | Sky Garden (roof) | 50,000 + rebirth 1 | wind gusts / greenhouse / floating island hops | 3 + 1 + the Secret | endgame |

**Why wings rather than one big map:** each wing is a fresh goal you can see ("I can almost afford the Arcade"), a fresh index page, and a fresh layout to learn. Speed upgrades pay off because the distances grow.

## 3. Progression systems

### 3.1 Speed (this milestone)

The whitepaper loop: faster → reach better creatures → more coins → faster.

| Track | Effect | Levels | Cost curve |
|---|---|---|---|
| **Sneakers** | walk and run speed when your hands are empty | 8 | 40 → 4,000 (about ×1.9 each) |
| **Steady Hands** | walking speed while carrying. Faster careful walking still counts as quiet | 5 | 120 → 3,200 |
| **Padded Shoes** | sprinting while carrying is 55% quieter | 1 | 60 |

Empty-handed speed is free to upgrade hard. Carrying stays a skill test: Steady Hands raises the safe pace but never makes running quiet.

### 3.2 Collection and forms

- **Rarity:** Common → Rare (stage, every ~70 s) → *Epic* (wing events) → *Legendary* (rotating Wanted) → *Secret* (Sky Garden, once an hour).
- **Forms, rolled when you bank:** Normal / Glazed ×2 / Jumbo ×3. Later Golden ×5 (events) and Rainbow ×10 (fuse 5 Golden).
- **Index:** one page per wing. Finishing a page pays a one-off reward: a coin bonus and a cosmetic trail. Form completion (every creature in Golden) is the grinder goal.
- **Evolutions:** one per wing. Each needs its buddy plus a route task: three vent rescues for King Rangoon, three ball-pit rescues for Jackpot Ticketoad.

### 3.3 Hideout display and idle income (next milestone)

Banked creatures can sit on **display shelves** in your hideout and earn coins per minute by rarity, form and wing. Offline earnings are capped at 2 hours.

- More shelves are bought with coins.
- It gives a reason to come back (collect earnings) and a reason to keep duplicates (better forms earn more).
- It gives your friends something to look at when they visit.

### 3.4 Rebirth: "Overtime" (endgame, for grinders)

Once you've unlocked the Cinema you can clock in for Overtime: coins, Sneakers and Steady Hands reset, while the index, buddies and shelves stay.

- Each Overtime gives +25% coins permanently and 1 Overtime token.
- Tokens buy permanent perks: a starting Sneakers level, an extra shelf, a faster rare timer, auto-collect for idle coins, and buddy slot 2.
- Overtime levels show next to your name on the leaderboard.

With a +25% linear multiplier, the economy can't snowball the way exponential prestige multipliers do. That kind of runaway has forced economy resets in other simulators.

### 3.5 Timers and events (the overlapping loops)

| Timer | Every | What happens |
|---|---|---|
| Rare stage | ~70 s per wing | a Rare sleeper with a beam of light |
| **Snack Rush** | 15 min | for 2 minutes, every sleeper in one wing is Glazed or better |
| **Wanted poster** | 1 hour | a specific creature and form pays ×3 |
| Secret sleeper | 1 hour (Sky Garden) | one Secret spawns for the whole server |
| Daily quests | daily | 3 quests: rescue 10, take the quiet route 3 times, catch a woken bolter |
| Login streak | daily | coins, then a cosmetic on day 7 |

**Healthy stopping points (whitepaper §5):** every event shows a clear "done" moment, and nothing is lost by leaving. Idle earnings are capped so nobody feels they must keep the game open.

### 3.6 Social

- The rare chase already makes other players matter (2-second exclusive window, then anyone can catch).
- **Next:** a "nudge". Bumping a carrier adds a little wake, so there's playful sabotage without stealing.
- **Later:** co-op carry (two players carry a Jumbo together, quieter), visiting hideouts, a server leaderboard, and trading (only once the economy is stable).

## 4. Interface direction

What the most-played Roblox games do well: one readable font, big rounded buttons on the left, currency at top centre, world labels floating over places, and every interaction marked by a glowing pad or prompt.

- **One font family:** Builder Sans, Roblox's own clean UI face. Extra Bold for titles and world labels, Bold for body text.
- **Light theme:** white rounded cards with a soft shadow, dark-ink text, and one pastel accent per element:
  - mint for good;
  - sky blue for info;
  - peach for shop;
  - lilac for the index;
  - sun yellow for coins.
  No heavy black outlines.
- **Floating place labels:** HIDEOUT, SHOP, FOOD COURT, ARCADE, COZY CORNER, BALL PIT and the RARE STAGE all float in the sky above the place in the same style and bob gently. You can always see where things are.
- **Walk-in pads:** step onto the glowing Shop pad in the hideout and the shop opens. The left rail buttons do the same from anywhere.
- **Less text and more shape:** icons plus 1–2 words. Prices are always on the button, and the "can afford" state is a filled button with a dot on the rail.

## 5. Milestones

| Milestone | Contents |
|---|---|
| **B1 "Bright & Big"** (this one) | light theme + one font + floating labels + walk-in shop; Sneakers / Steady Hands speed tracks; faster base speed; the Arcade wing (3 creatures + 1 evolution, its own rare stage, ball pit, dance floor, paid gate); per-wing rare timers; save schema extended (old saves load fine) |
| B2 "Home" | hideout display shelves + idle and offline income, daily quests, login streak, index page rewards + trails (**built**) |
| B3 "Toy Barn" | wing 3 (**built**: squeaky aisle, Plush Mountain, Toy Stage, 3 creatures + Squeakicorn Royale), Snack Rush events, Wanted posters, nudge (**built**) |
| B4 "Overtime" | rebirth + token perks (**built**; needs the Toy Barn and 50,000 coins until the Cinema exists); leaderboard; Golden form |
| B5 "Cinema" | wing 4 + co-op carry + Rainbow fusion |
| B6 "Sky Garden" | wing 5 + Secret sleepers + hideout visits; trading if the economy holds up |

## 6. Technical constraint to solve before wing 3

The creatures are rebuilt at runtime from baked mesh data, which needs no uploads, but a Roblox client can hold only about 8 such runtime meshes at once. B1 works around this:

- the Index and reveal card use pre-rendered portraits;
- meshes are pooled, so only the wing you're in is loaded.

Three or more wings, or several buddies on screen, will need the models imported as real Roblox mesh assets: File → Import 3D in Studio, from your account. Imported meshes have no such limit.

## 7. Rough pacing targets (to tune in playtests)

| Goal | Target time |
|---|---|
| First rescue | under 1 minute |
| Padded Shoes | ~3 minutes |
| Sneakers 3 | ~8 minutes |
| Arcade unlock | ~10–12 minutes |
| King Rangoon | ~20 minutes |
| Food Court + Arcade index (Normal forms) | ~45 minutes |
| Jackpot Ticketoad + Sneakers 8 | ~1.5 hours |
| Toy Barn | ~2 hours |
| First Overtime | ~6–8 hours |
| Full Golden index | weeks |
