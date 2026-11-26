# Importing Meshy models into Roblox

> **Update 2026-11-26:** Claude now uploads creature models itself, through Studio's MCP Open Cloud permissions: `asset:read`/`asset:write`, with `art/meshy/models` approved under MCP Permissions → Open Cloud upload directories. You approve each batch. The manual steps below remain as a fallback. The first 12 creatures are uploaded and listed in `src/shared/CreatureAssets.luau` and `art/meshy/ledger.json`.

Why: the game currently rebuilds creatures at runtime from baked data, and a Roblox client can only hold about 8 of those. Uploaded mesh assets have no such limit, which the monster game needs (3 followers per player, other players' teams, wild packs).

Uploading puts the files on **your** Roblox account. That's why you do this part: Claude doesn't upload anything to Roblox for this project.

---

## Part 1: get the model file

**The 12 existing creatures (1–2★ filler)** are already downloaded. You don't need Meshy for these. Each one is at:

```
~/roblox-game/art/meshy/models/<name>/model.glb
```

(crab_rangoon, crocsquatch, mall_gobstopper, king_rangoon, ticketoad, joystingray, clawmato, jackpot_ticketoad, squeakicorn, yoyoctopus, blockodile, squeakicorn_royale)

**New core monsters (3–5★):** Claude generates them through the Meshy tools and saves them into the same folder layout. If you'd rather download one yourself from the Meshy website:

1. Go to **meshy.ai**, sign in, and open **My Assets** (or the workspace where the model is).
2. Open the model.
3. If it should move (core monsters): use Meshy's **Rig / Animate** option first, so the download includes a skeleton and animation clips. Do this for walk, idle and attack if they're offered.
4. Click **Download** and pick a format:
   - **FBX** for rigged and animated models (it carries the skeleton and clips);
   - **GLB** for static models.
   - Texture size: **1024** is enough, since Roblox shrinks anything larger to 1024.
5. Save it as `~/roblox-game/art/meshy/models/<name>/model.fbx` (or `.glb`) so it's kept in the repo.

---

## Part 2: import into Roblox Studio

1. Open the game (**dopatesta**) in Roblox Studio, signed in as the account that owns it. Assets only load in games owned by the account (or group) that uploaded them.
2. Make sure you're in **Edit** mode, not playing.
3. Click **Import 3D**:
   - **Home** tab → **Import 3D**, or
   - in the new Studio UI: the **File** menu (top-left) → **Import 3D**.
4. Choose the file (`model.glb` or `model.fbx`). The **3D Importer** window opens with a preview.
5. Check the preview. The model should look right (textured, not grey). If it's sideways or tiny, that's fine; the game sizes and turns models in code.
6. Settings to check, near the top of the settings list. Leave anything else at its default.
   - **Insert in Workspace / Insert using scene position**: on, so you can see it.
   - **Anchored**: on.
   - **Rig**: for static models, no rig. For a rigged FBX, let it import the rig (skinned mesh).
   - **Upload to**: your account (it's usually already selected).
7. Click **Import**. Studio uploads the mesh and texture to your account, which takes a few seconds, and drops a **Model** into the Workspace.
8. **Rename** the Model in the Explorer to the creature's ID, with no spaces, exactly like this:
   `CrabRangoon`, `Crocsquatch`, `MallGobstopper`, `KingRangoon`, `Ticketoad`, `Joystingray`, `Clawmato`, `JackpotTicketoad`, `Squeakicorn`, `Yoyoctopus`, `Blockodile`, `SqueakicornRoyale`
   (New core monsters will get IDs when they're designed.)
9. In the Explorer, right-click **ReplicatedStorage** → **Insert Object** → **Folder**, and name it **CreatureModels**. You only need to do this once.
10. Drag the renamed Model into **ReplicatedStorage → CreatureModels**.
11. Repeat steps 3–10 for each model.
12. Save the place: **File → Publish to Roblox**. Without this, the imported models are lost when Studio closes.

When you're done, tell Claude. It will:
- read the uploaded asset IDs through the Studio connection;
- record them in the code, so they're also in git;
- switch the game from the runtime-built meshes to the uploaded ones.

---

## Good to know

- **Moderation:** new uploads are checked by Roblox. A model can show up blank or grey for a few minutes until it's approved.
- **Limits:**
  - up to about 20,000 triangles per mesh (our creatures are about 5,000; core monsters will be 10–15k);
  - textures are capped at 1024×1024.
- **Where they live:** uploaded meshes and images appear in **Toolbox → Inventory** (My Meshes / My Images) and in the **Asset Manager**.
- **Rojo is safe:** live sync only manages `ReplicatedStorage/Shared`, so it won't delete `CreatureModels`.
- **Animations (rigged core monsters):** each clip (idle, walk, attack…) also has to be published as an **Animation** asset to get an ID. In Studio: **Avatar** tab → **Animation Editor** → select the imported rig → **⋯ → Import → From FBX Animation** → **⋯ → Publish to Roblox**. We'll go through this step by step when the first rigged monster is ready.
- **Don't** use Studio's AI "generate" tools or the Meshy Studio plugin. The project only allows the Rojo plugin, and the manual import above keeps everything under your control.
