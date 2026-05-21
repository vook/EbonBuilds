# EbonBuilds

A **build-based echo automation addon** for **[ProjectEbonhold](https://github.com/vook/EbonBuilds)**, a World of Warcraft 3.3.5a (Wrath of the Lich King) roguelite server.

The addon lets you create *builds* — class-specific profiles that tell the automation engine exactly how to handle every echo choice during a run. The name EbonBuilds comes from the core idea behind the project: making it easy for players to share builds with each other. Even though public build sharing was the last feature implemented, it was always the goal.

---

## Getting Started

### Opening the Addon

Click the **minimap button** (book icon) or type `/ebb` to toggle the main window.

### Creating a Build

Click **+ New Build** in the left panel to open the editor. The editor is split into four tabs:

**Overview** — Set your **class**, **specialization**, **locked echoes**, and **description**. Locked echoes are the ones you want to lock in your inventory during a run; they have the highest selection priority in the automation pipeline. The description field is your space to document what the build needs: recommended items, affixes, rotation priorities, glyphs — anything another player would need to know.

**Echoes** — Fine-tune your build echo by echo. Assign a weight to each echo and see its calculated score across all five quality tiers (Common through Legendary). The higher the weight, the more the automation engine favors that echo.

**Bonus** — Apply batch scoring modifiers based on echo characteristics like quality tier and family. These bonuses layer on top of individual weights. Each modifier has two modes: **additive** (the default) adds the bonus value directly to the echo's base score — an echo with 100 score and a +20 rarity bonus becomes 120. **Multiplicative** multiplies the base weight by the bonus: an echo with 100 base weight and a 0.2 multiplier gets 100 + 20 = 120. When the base weight is zero, multiplicative bonuses contribute nothing since only the base is multiplied; additive bonuses from other sources are ignored in the multiplication. There is also a **novelty** bonus, designed specifically for the Adaptive Power echo, which rewards unique echoes. If an echo is not already on your picked list, the novelty value is added to its total score — so an echo with 100 base score and 50 novelty will show 150 the first time it appears.

**Automation** — Configure the thresholds that control how the addon reacts when echoes are offered. Set up family banish protection (echoes belonging to protected families are never banished, even if manually added to the ban list), a ban list of echoes that should never be picked, and the core automation thresholds. All thresholds use **peak** as their reference point — peak is the highest possible echo score for your class after all calculations except novelty. Auto-reroll triggers when the sum of all offered echo scores falls below a configurable percentage of peak (range: 50%–300%). Auto-banish removes echoes scoring below a percentage of peak. Auto-freeze activates when two or more echoes in the same pool score above the threshold — the lower-scored one is frozen and the highest is selected. Frozen echoes receive a score penalty for the next round, reducing their priority until they are eventually picked.

When you are done configuring, click **Save**. You can mark the build as **Public** if you want it to appear in the public builds browser for other players. However, to prevent a flood of untested builds, only *validated* builds are shared — a build becomes validated when its creator reaches level 80 with it after starting from level 1.

### Importing a Build

Click **Import Build** above the build list and paste a base64-encoded export string.

### Exporting a Build

While editing a build, click **Export** (bottom-left corner) to generate a base64 string you can share.

---

## Automation Pipeline

When echoes are offered during a run, the automation engine evaluates every choice against your active build. It follows a strict priority pipeline with a short delay to ensure server data is ready:

1. **Locked Echo pre-check** — if an offered echo matches one of your locked echoes, it is selected immediately.
2. **Banish** — echoes scoring below the auto-banish threshold are banished, lowest score first. Ban-list echoes take priority. Echoes whose families match the banish protection whitelist are skipped.
3. **Reroll** — if the sum of all offered echo scores falls below the auto-reroll threshold, a reroll is requested.
4. **Freeze** — if at least two offered echoes score above the auto-freeze threshold, the lower-scored one is frozen and the highest is selected.
5. **Select** — falls back to picking the highest-scored non-banned echo.

A toast notification appears after each automated action showing the three offered echoes, the target highlighted, and your remaining charges.

---

## Build List & Overview

The **left panel** lists all your builds — created or imported. Click any build to load it; the active build is the one driving automation. You can toggle automation on or off per build directly from the overview.

Clicking a build opens the **Overview** tab with class, spec, author, last modified, locked echoes, and the automation toggle. Three additional sub-tabs are available:

**Stats** — echoes seen, runs completed, picks, rerolls/banishes/freezes used, quality distribution, and the most picked and banned echoes. (Some counters are not yet fully wired and will be updated in a future version.)

**Missing** — all echoes your build does not yet have, sorted by score. Echoes at the top have the highest acquisition priority.

**Logbook** — the full session history embedded in the overview. A session starts at level 1 and ends when your character dies and resets. Every automation action is recorded with echo names, scores, target highlights, and remaining charges. You can export, delete individual entries, or clear all logs.

---

## Public Builds & Sync

The **Public Builds** screen (accessible from the button above the build list) shows builds shared by other players. You can filter by class and specialization. Each build card shows an **Import** button for new builds, an **Update** button when a newer version is available, or a **Loaded** label when you are already up to date.

> **Important:** Sync is peer-to-peer — there is no central server. At least one player must have public builds available and be online at the same time as you for any builds to appear. Until a few players act as seeds by sharing their builds, the list will be empty. Once builds start circulating and players import them, the network becomes self-sustaining. If you see an empty list, it simply means no seed player is currently online — try again later or ask a friend to share their builds.

Sync uses a hidden in-game channel to discover peers. Due to limitations in the addon communication API, it only runs when you click the **Reload** button on the Public Builds screen. Only builds updated within the last 60 days are shown, and the addon always fetches the most recent version of each build. Loading may feel slightly slow — the addon is working within tight constraints and the protocol had to be quite creative to function reliably.

> **Early release:** The sync system is not yet final. Bugs may occur. If you encounter issues, please report them so they can be fixed.

**Validation requirement:** only builds that have reached level 80 with their creator are shared. This prevents untested or incomplete builds from flooding the public list.

When you edit a build you imported from another player, the build becomes yours: it gets a new identity, your name as the author, and must be re-validated (level 1 to 80) before it can be shared publicly again. The original author's name is kept in the build's lineage so you always know who you forked from.

---

## Commands

| Command | Description |
|---|---|
| `/ebb` | Toggle the EbonBuilds main window |
| `/ebbsync join` | Show how to join the sync channel |
| `/ebbsync status` | Show sync channel status |
| `/ebbsync reset` | Reset sync cooldown and lastSyncDate; clears remote builds |
| `/ebbsync verbose` | Toggle verbose logging for sync diagnostics |

---

## Dependencies

- **[ProjectEbonhold](https://github.com/vook/EbonBuilds)** (version 28+, Interface 30300) — provides the echo database, perk service API, run data, and shared utilities

---

## Saved Variables

`EbonBuildsDB` — persisted per-account:

| Field | Description |
|---|---|
| `builds` | All locally-owned builds (created + imported), keyed by ObjectId |
| `activeBuildId` | Currently active build driving automation |
| `sessions` | Session history logs |
| `pendingWeights` | Staging area for echo weights during editing |
| `_isEditingBuild` | Flag indicating edit/create mode is active |
| `remoteBuilds` | Builds received via sync, not yet imported — keyed by source ObjectId |
| `lastSyncDate` | ISO timestamp of last successful sync |
| `syncPeers` | Known responder names for fallback discovery |
| `syncVersion` | Tracks the last `SYNC_VERSION` — bumping it purges `remoteBuilds` |
| `minimapAngle` | Minimap button position |
