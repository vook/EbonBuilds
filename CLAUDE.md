# EbonBuilds — WoW 3.3.5a AddOn

## Project Overview

This is a **World of Warcraft 3.3.5a addon** written in **Lua**. It depends on **ProjectEbonhold** as an external addon.
All project text, code identifiers, comments, commit messages, and documentation must be written in **English**, unless the user explicitly requests otherwise.

---

## Language Policy

- All source code, comments, variable names, and documentation: **English**
- User communication: follow the user's language (default: Brazilian Portuguese)
- Commit messages: **English**, following Conventional Commits

---

## Workflow: Three-Agent Pipeline

Every development request follows a strict three-agent pipeline. Agents are spawned sequentially — each depends on the previous one's output.

---

### Agent 1 — Software Architect

**Role:** Lead the development planning and define the implementation strategy.

**Responsibilities:**
- Index and maintain project information to facilitate future sessions
- Lead the development request analysis
- Define folder structure and decide the best approach for each change
- Maximize modularity and human readability
- **Never infer missing information** — if something is unclear, ask the user
- **Never adapt code knowing the information is incoherent** — flag the issue and wait for clarification
- Suggest solutions when the path is unclear, but always confirm with the user before proceeding
- Present the full plan to the user and wait for explicit approval before passing instructions to Agent 2

**Output:** Approved implementation plan passed to Agent 2.

---

### Agent 2 — WoW AddOn Developer

**Role:** Execute the plan defined by Agent 1.

**Responsibilities:**
- Implement using standard WoW 3.3.5a addon development patterns
- Maximize project modularity
- Enforce cyclomatic complexity limits:
  - **≤ 20 per function**
  - **≤ 200 per file**
- Apply **SOLID principles** wherever applicable
- If any instruction from Agent 1 is contradictory or causes a collision, surface the problem to the user with options — do not silently resolve it
- Use the WoW 3.3.5a API (no APIs introduced after patch 3.3.5a)

**Output:** Change report passed to Agent 3.

---

### Agent 3 — Quality Assurance

**Role:** Validate what was built against what was planned and requested.

**Responsibilities:**
- Compare Agent 2's change report against Agent 1's approved plan
- Verify all changes via `git diff` / `git log` against the report
- Inform the user if the delivery does not match the request, offering the option to retry or keep as-is
- On user request, produce a **Conventional Commits** message:
  - **Title:** most impactful single change
  - **Body (bullet points):** major specific changes only — no noise
  - Message must be in **English**

---

## WoW 3.3.5a Development Standards

- Use only APIs available in patch **3.3.5a** (WotLK)
- Follow standard addon structure: `.toc`, core file, modular Lua files
- Use `AceAddon-3.0`, `AceDB-3.0`, `AceConsole-3.0`, `AceEvent-3.0` libraries where applicable (confirm with user if a library is needed)
- Frame and widget creation must use the WoW XML or Lua widget API for 3.3.5a
- SavedVariables must be declared in the `.toc` file

## Folder Structure Convention

```
EbonBuilds/
  EbonBuilds.toc
  core/
    Init.lua          -- addon initialization
    Events.lua        -- event registration and dispatch
  modules/
    <ModuleName>/
      <ModuleName>.lua
  libs/               -- embedded libraries (Ace3, etc.)
  media/              -- textures, sounds, fonts
```

Structure may evolve — Agent 1 defines and updates it per request.

---

## General Rules

- Do not infer or assume missing information — ask the user
- Do not silently resolve incoherent instructions — flag them
- Do not add unrequested features, abstractions, or error handling
- Do not add comments that only describe what the code does — only add comments for non-obvious WHY
- No trailing summaries of what was done unless the user asks

---

## Dependency: ProjectEbonhold

**Source path (decrypted reference):** `C:\Ebonhold\Data\patch4_out\Interface\AddOns\ProjectEbonhold`
**Interface version:** 30300 (WoW 3.3.5a) | **Addon version:** 28

The main namespace is the global table `ProjectEbonhold`. All interaction with the parent addon goes through this table.

### Communication Pattern

```lua
-- Send a request to the server
ProjectEbonhold.sendToServer(requestCode, bodyString)

-- Register a handler for a server response
ProjectEbonhold.onEventReceived(responseCode, function(body, dist, sender, evt) end)
```

- Message prefix: `"AAM0x9"` (WHISPER channel to self)
- Max payload: 240 bytes (auto-chunked at 180 bytes)

---

### Client → Server Request Codes (`ProjectEbonhold.CS`)

| Constant | Value | Description |
|---|---|---|
| `SEND_HI` | 0 | Handshake |
| `REQUEST_PLAYER_RUN_DATA` | 14 | Get current run data |
| `REQUEST_PLAYER_PERK_CHOICE` | 16 | Request an echo selection |
| `REQUEST_PLAYER_PERK_SELECTION` | 17 | Select a specific echo |
| `REQUEST_PLAYER_GRANTED_PERKS` | 18 | Get owned echoes |
| `REQUEST_REROLL` | 27 | Reroll current echo choices |
| `REQUEST_LOCK_PERK` | 30 | Lock an echo in inventory |
| `REQUEST_UNLOCK_PERK` | 31 | Unlock an echo from inventory |
| `REQUEST_BANISH_PERK` | 203 | Banish an echo from the current run |
| `REQUEST_DEV_ADD_PERK_STACK` | 204 | (Dev) Add perk stack |
| `REQUEST_DEV_REMOVE_PERK_STACK` | 205 | (Dev) Remove perk stack |
| `REQUEST_FREEZE_PERK` | 207 | Freeze an echo to carry over |
| `REQUEST_OBJECTIVES_PROPOSALS` | 200 | Get objective proposals |
| `REQUEST_SELECT_OBJECTIVE` | 201 | Select an objective |
| `REQUEST_REROLL_OBJECTIVES` | 206 | Reroll objectives |
| `REQUEST_HARDMODE_DATA` | 300 | Get hardmode/torment data |
| `REQUEST_HARDMODE_SET_DIFFICULTY` | 301 | Set hardmode difficulty |
| `REQUEST_AFFIX_EXTRACTION` | 310 | Extract an affix |
| `REQUEST_AFFIX_APPLY` | 312 | Apply an affix |
| `REQUEST_LEARNED_AFFIXES` | 313 | Get learned affixes |
| `REQUEST_UNLEARN_SPELL_ECHOES` | 315 | Unlearn spell echoes |
| `REQUEST_INSTANCE_RESET_ALL` | 601 | Reset all instances |
| `REQUEST_ACCEPT_DEATH` | 26 | Accept death |
| `REQUEST_VERSION_CHECK` | 29 | Check addon version |
| `REQUEST_SET_USING_VOID_STORAGE` | 50 | Configure void storage |
| `REQUEST_RETRIEVE_VOID_STORAGE_ITEM` | 51 | Retrieve void storage item |

---

### Server → Client Response Codes (`ProjectEbonhold.SS`)

| Constant | Value | Description |
|---|---|---|
| `SEND_ACKNOWLEDGEMENT` | 0 | Generic ack |
| `SEND_PLAYER_RUN_DATA` | 13 | Run data payload |
| `SEND_PLAYER_PERK_CHOICE` | 16 | Echo choices offered to player |
| `SEND_PLAYER_PERK_SELECTION_RESULT` | 1000 | Result of echo selection |
| `SEND_PLAYER_PERK_GRANTED` | 18 | Echo was granted |
| `SEND_BANISH_REPLACEMENT_PERK` | 103 | Replacement echo after banish |
| `SEND_FREEZE_PERK_RESULT` | 104 | Result of freeze action |
| `SEND_INSTANCE_ENTERED` | 9 | Player entered an instance |
| `SEND_HARDMODE_DATA` | 500 | Hardmode data |
| `SEND_HARDMODE_SET_RESULT` | 501 | Hardmode set result |
| `SEND_AFFIX_EXTRACTION_RESULT` | 510 | Affix extraction result |
| `SEND_AFFIX_APPLY_RESULT` | 512 | Affix apply result |
| `SEND_LEARNED_AFFIXES` | 513 | Learned affixes list |
| `SEND_OBJECTIVES_PROPOSALS` | 101 | Objective proposals |
| `SEND_CURRENT_OBJECTIVE` | 102 | Current active objective |
| `SEND_CONTENT_VOID_STORAGE` | 100 | Void storage contents |
| `SEND_WRONG_PATCH` | 33 | Wrong patch version |
| `SEND_PLAYER_IS_BLOCKED` | 900 | Player is blocked |
| `SEND_UNLEARN_SPELL_RESULT` | 515 | Unlearn spell result |
| `SEND_INSTANCE_RESET_RESULT` | 701 | Instance reset result |

---

### Public Service API

#### `ProjectEbonhold.PerkService`

```lua
-- Echo choices
RequestChoice()                   -- Request new echo selection from server
SelectPerk(spellId)               -- Select an echo; returns boolean (success queued)
GetCurrentChoice()                -- Returns Perks.currentChoice array
FreezePerk(perkIndex)             -- Freeze echo at 0-based index; returns boolean
BanishPerk(perkIndex)             -- Banish echo at 0-based index; returns boolean
RequestReroll()                   -- Request reroll; returns boolean

-- Owned echoes
RequestGrantedPerks()             -- Request owned echoes from server
GetGrantedPerks()                 -- Returns Perks.grantedPerks table (keyed by spell name)
GetLockedPerks()                  -- Returns Perks.lockedPerks table
GetMaximumPermanentEchoes()       -- Returns max echo slots (Perks.maximumPermanentEchoes)
LockPerk(spellId, count)          -- Lock echo in inventory
UnlockPerk(spellId)               -- Unlock echo from inventory

-- Reroll info
GetPendingRollsCount()            -- Returns remaining rolls for this level
GetRollsDebugInfo()               -- Returns (level, picksMade, rollsLeft)
ResetPicksMade()                  -- Reset internal pick counter
```

#### `ProjectEbonhold.PerkUI`

```lua
Show(choices)                     -- Display echo selection UI
Hide()                            -- Hide echo selection UI
UpdateSinglePerk(perkIndex, data) -- Animate single card replacement (after banish)
ApplyRankGlows()                  -- Apply border glow to quality cards
ApplyScale(scale)                 -- Set UI scale (0.5–3.0)
ResetSelection()                  -- Re-enable all interaction after failed pick
RefreshBanishText()               -- Update banish button text and state
```

#### `ProjectEbonhold.PerkDatabase`

```lua
-- PerkDatabase[spellId] = {
--   maxStack   = number,
--   classMask  = number,   -- class bitmask (1=Warrior, 2=Paladin, 4=Hunter, 8=Rogue,
--                          --   16=Priest, 32=DK, 64=Shaman, 128=Mage, 256=Warlock,
--                          --   1024=Druid, 1535=all classes)
--   minLevel   = number,
--   quality    = number,   -- 0–4
--   groupId    = number,   -- mutually exclusive group (nil if none)
--   requiredSpell = number,
--   comment    = string,   -- display name
--   families   = {string, ...}
-- }
```

#### `ProjectEbonhold.PlayerRunService`

```lua
GetCurrentData()  -- Returns currentRunData:
-- {
--   usedRerolls      = number,
--   totalRerolls     = number,
--   usedFreezes      = number,
--   totalFreezes     = number,
--   remainingBanishes = number,
-- }
```

---

### Runtime Global Tables (set by ProjectEbonhold)

```lua
_G["EbonholdPlayerRunData"] = {
  usedRerolls       = number,
  totalRerolls      = number,
  usedFreezes       = number,
  totalFreezes      = number,
  remainingBanishes = number,
}

_G["EbonholdIntensityData"] = {
  intensity      = number,
  areaNameReaper = string,
  zoneNameReaper = string,
}

_G["EbonholdAutoShowDB"] = {
  enabled = boolean,  -- auto-show echo UI without clicking the button
}
```

---

## Echo System Reference

### What Is an Echo

An **Echo** (internal name: "perk") is a persistent character ability granted during a run. Each echo has:
- A **Spell ID** (server-side spell, range ~200000–201220+)
- A **Quality tier** (0–4)
- A **Stack count** (how many the player owns) and **max stack**
- One or more **families**
- Optional **class restriction** (bitmask) and **minimum level**

---

### Echo Families

Each echo can belong to multiple families simultaneously.

| Family name (code) | Display |
|---|---|
| `"Tank"` | Tank |
| `"Survivability"` | Survivability |
| `"Healer"` | Healer |
| `"Caster"` / `"Caster DPS"` | Caster DPS |
| `"Melee"` / `"Melee DPS"` | Melee DPS |
| `"Ranged"` / `"Ranged DPS"` | Ranged DPS |

Family membership affects:
1. **Reroll odds** — rerolling reduces odds of the same families appearing next
2. **UI icons** — up to 5 family icons shown per echo card
3. **Player synergy** — players build toward families matching their role

---

### Echo Quality Tiers

| Value | Name | Color | Hex |
|---|---|---|---|
| 0 | Common | White | `ffffff` |
| 1 | Uncommon | Green | `19ff19` |
| 2 | Rare | Blue | `0066ff` |
| 3 | Epic | Purple | `cc66ff` |
| 4 | Legendary | Orange | `ff8000` |

---

### Echo States

| State | Description |
|---|---|
| `isFrozen` (value 1) | Echo is locked to carry over to next selection |
| `isCarried` (value 2) | Echo was carried forward from a previous freeze |
| `justFrozen` | Newly frozen this turn — UI applies crossfade visual |
| `_locallyFrozen` | Client-side optimistic flag before server confirmation |

---

### Echo Data Structures

**Echo choice object (received from server):**
```lua
{
  spellId   = number,
  quality   = number,   -- 0–4
  isFrozen  = boolean,  -- server value 1
  isCarried = boolean,  -- server value 2
  justFrozen = boolean, -- client-side only
  stack     = number,
  maxStack  = number,
}
```

**Server response format for `SEND_PLAYER_PERK_CHOICE`:**
```
"N|spellId,quality,frozen;spellId,quality,frozen;..."
N = optional pending rolls count
frozen = 0 (none), 1 (frozen), 2 (carried)
```

**Granted perk (owned echo) — stored in `Perks.grantedPerks[spellName]`:**
```lua
{ spellId = number, stack = number, maxStack = number, quality = number }
```

---

### Echo Actions — Full Flow

#### When echoes are offered

Echoes are offered to the player in two cases:
1. `PLAYER_LEVEL_UP` event fires
2. `PLAYER_ENTERING_WORLD` fires and a pending choice exists

In both cases `ProjectEbonhold.PerkService.RequestChoice()` is called, which sends `CS.REQUEST_PLAYER_PERK_CHOICE` to the server.

---

#### Select

```
CS.REQUEST_PLAYER_PERK_SELECTION (17) → tostring(spellId)
SS.SEND_PLAYER_PERK_SELECTION_RESULT (1000) ← "1" success | "0" failure
```

Flow:
1. Validate `spellId` exists in `Perks.currentChoice`
2. Set `Perks.pendingSelectSpellId = spellId`
3. Send request
4. On success: hide UI, auto-request next choice via `RequestChoice()`
5. On failure: call `PerkUI.ResetSelection()` to re-enable buttons

---

#### Freeze

```
CS.REQUEST_FREEZE_PERK (207) → tostring(perkIndex)   -- perkIndex is 0-based
SS.SEND_FREEZE_PERK_RESULT (104) ← "1" success | other = failure
```

Validation (client-side before send):
- `totalFreezes - usedFreezes > 0`
- `perkIndex` must be 0, 1, or 2

Flow:
1. Optimistically increment `runData.usedFreezes`
2. Set `_locallyFrozen = true` on the card frame
3. Apply freeze visual (crossfade, 0.45s duration, ice icon, blue border)
4. On server failure: decrement `runData.usedFreezes`, refresh full UI

---

#### Reroll

```
CS.REQUEST_REROLL (27) → ""
SS.SEND_PLAYER_PERK_CHOICE (16) ← new choices (same format as initial offer)
```

Validation:
- `Perks.pendingReroll` must be false (no in-flight request)

Notes:
- Tracked via `runData.usedRerolls` / `runData.totalRerolls`
- Rerolls reset on death
- Current families' draw odds are reduced for next reroll

---

#### Banish

```
CS.REQUEST_BANISH_PERK (203) → tostring(perkIndex)   -- perkIndex is 0-based
SS.SEND_BANISH_REPLACEMENT_PERK (103) ← "newSpellId,newQuality" | "0" failure
```

Validation:
- `ProjectEbonhold.Constants.ENABLE_BANISH_SYSTEM == true`
- `runData.remainingBanishes > 0`
- Card must not be frozen or carried

Flow:
1. Send request
2. On success: parse `newSpellId,newQuality`, call `PerkUI.UpdateSinglePerk(perkIndex, newData)`
3. On failure (`newSpellId == 0`): call `PerkUI.ResetSelection()`

---

### Echo Action Summary Table

| Action | CS code | SS code | Key validation | Success | Failure |
|---|---|---|---|---|---|
| Request choices | 16 | 16 | — | Show UI | Hide UI |
| Select echo | 17 | 1000 | Valid spellId in currentChoice | Next choice | ResetSelection() |
| Freeze echo | 207 | 104 | Freezes remaining, valid index | Apply visual | Undo + refresh UI |
| Reroll | 27 | 16 | No pending reroll | New choices | Notify (0 left) |
| Banish echo | 203 | 103 | Banishes remaining, not frozen | Update card | ResetSelection() |

---

### Constants

```lua
ProjectEbonhold.Constants = {
  MAX_INTENSITY         = 475,
  MAX_SOUL_ASHES        = 89701360,
  INTENSITY_LEVEL_1     = 75,
  INTENSITY_LEVEL_2     = 200,
  INTENSITY_LEVEL_3     = 275,
  INTENSITY_LEVEL_4     = 400,
  INTENSITY_LEVEL_5     = 475,
  ENABLE_BANISH_SYSTEM  = true,
}
```

---

### SavedVariables (ProjectEbonhold)

**Global (`ProjectEbonholdDB`):**
```lua
{
  perkPicksMade            = { ["realm\tname"] = number },
  perkLastLevel            = { ["realm\tname"] = number },
  perkFamilyHintDismissed  = boolean,
  perkUIScale              = number,  -- 0.5–3.0
}
```

**Per-character:** `ActionBarSaverDB`

---

### Slash Commands (ProjectEbonhold)

| Command | Alias | Effect |
|---|---|---|
| `/projectebonhold` | `/peb` | Open options panel |
| `/kb` | `/knowledgebase` | Open knowledge base |
| `/sell_junk` | — | Sell junk items |

---

### Echo Chat Link Format

```lua
-- Written in chat:  {echo:spellId:quality}
-- Rendered as:      |cffCOLOR|Hecho:spellId|h[SpellName]|h|r
-- Clicking opens the spell tooltip via SetHyperlink("spell:" .. spellId)
```
