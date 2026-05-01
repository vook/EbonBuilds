# EbonBuilds

A **build-based echo automation addon** for **[ProjectEbonhold](https://github.com/vook/EbonBuilds)**, a World of Warcraft 3.3.5a (Wrath of the Lich King) roguelike server.

EbonBuilds lets you create *builds* — class-specific profiles with weighted echo preferences, scoring rules, and automation thresholds. When echoes are offered during a run, the automation engine evaluates every choice against your active build and executes the optimal action automatically.

---

## Getting Started

### Opening the Addon

Click the **minimap button** (book icon) or type `/eb` to toggle the main window.

### Creating a Build

1. Click **+ New Build** in the left panel.
2. Choose your **class** and **specialization**.
3. Give it a **title** and optionally a **description**.
4. Switch to the **Echoes** tab and assign **weights** to echoes you want.
5. Switch to the **Bonus** tab to configure scoring modifiers.
6. Switch to the **Automation** tab to set thresholds and protection rules.
7. Click **Save**.

### Importing a Build

Click **Import Build** above the build list and paste a base64-encoded export string.

### Exporting a Build

While editing a build, click **Export** (bottom-left corner) to generate a base64 string you can share.

---

## Features

### Build Management
- Create, edit, and delete builds
- Class-colored cards in the build list with class icon, spec icon, and locked echoes
- Per-build echo weights, scoring settings, and automation thresholds
- Toggle automation on/off per build from the overview

### Echo Table & Filters
- Full echo list sourced from ProjectEbonhold's PerkDatabase
- Class-filtered: only shows echoes available to your current class
- Quality-tier scores displayed per echo (Common through Legendary)
- Icon tooltips with resolved spell descriptions (via `utils.GetSpellDescription`)
- Search filter by echo name
- Quality dropdown filter
- Family multi-select dropdown filter (Tank, Survivability, Healer, Caster DPS, Melee DPS, Ranged DPS, No family)

### Scoring System
- **Base weight**: assign a numerical weight to each echo (0–999999)
- **Quality bonuses**: per-tier additive or multiplicative bonuses
- **Family bonuses**: per-family additive or multiplicative bonuses (Tank, Survivability, Healer, Caster, Melee, Ranged, No family)
- **Novelty bonus**: additive or multiplicative bonus applied on top
- **Peak score**: best possible echo score for the current class (used for threshold scaling; excludes novelty)

### Automation Engine
The automation engine runs every time echoes are offered. It follows a strict priority pipeline with a 2-second evaluation delay to ensure server data is ready:

1. **Locked Echo pre-check**: if an offered echo matches a locked echo slot, it is selected immediately.
2. **Banish**: banishes echoes below the auto-banish threshold (lowest score first). Ban-list echoes take priority. Echoes with families matching the banish protection whitelist are skipped.
3. **Reroll**: if the sum of offered echo scores is below the auto-reroll threshold, a reroll is requested.
4. **Freeze**: if at least two offered echoes score above the auto-freeze threshold, the lower-scored ones are frozen and the highest is selected after the evaluation delay. A configurable freeze penalty is applied to frozen echoes.
5. **Select**: falls back to selecting the highest-scored non-banned echo (or a random one if all are banned and ban-all mode is set to random).

Toast notifications appear after each automated action, showing the three offered echoes, the target echo highlighted, and remaining charges (banish, reroll, freeze).

### Automation Settings
- **Auto-banish %**: banish echoes scoring below this percentage of peak
- **Auto-reroll %**: reroll when the best offered echo is below this percentage of peak
- **Auto-freeze %**: freeze echoes scoring above this percentage of peak
- **Freeze penalty %**: score reduction applied to frozen echoes
- **Banish family protection**: per-family whitelist — any echo with at least one protected family is never banished nor selected
- **Echo ban list**: manually ban specific echoes (right-click to remove)
- **Ban-all mode**: when all offered echoes are banned, pick the highest score or a random one

### Locked Echoes
- Configure up to 4 locked echoes per build
- Echo picker with quality filtering and ban-list awareness
- Locked echoes are auto-selected when offered
- Displayed in the build list, build editor, and build overview

### Build Overview
Three-tab dashboard for the active build:
- **Overview**: class, spec, author, last modified, description, locked echoes, automation toggle
- **Stats**: echoes seen, runs completed, picks, rerolls/banishes/freezes used, quality distribution, most picked/banned echoes, missing echoes with drop sources sorted by score
- **Logbook**: full session history embedded in the overview

### Session History
- Automatic session tracking: a session begins at level 1 and ends when the player dies and resets to level 1
- Per-session log of every automation action with echo names, scores, target highlight, and remaining charges
- Session cards showing character name, class, build title, level range, soul ashes, and duration
- Live-refreshing log view while the window is open
- Export session to a text file
- Delete individual sessions or log entries

### Export / Import
- Export builds to base64-encoded JSON (echoes without weight are excluded to keep payloads small)
- Import builds from base64 strings pasted into the import dialog
- All settings, weights, locked echoes, and automation configuration are preserved

### Toast Notifications
- Action summaries with inline echo names, scores, and target highlighting
- Remaining charges display (banish, reroll, freeze)
- Auto-dismiss after 3 seconds, pause on mouseover, click to dismiss

---

## Planned Features

- **Public builds browser**: browse and import builds shared by other players (button placeholder exists on the welcome screen)
- **Configurable evaluation delay**: expose the 2-second automation delay as a user setting
- **Build versioning and change history**: track and review build changes over time
- **Multi-build comparison**: compare scoring differences between builds side-by-side

---

## Dependencies

- **[ProjectEbonhold](https://github.com/vook/EbonBuilds)** (version 28+, Interface 30300) — provides the echo database, perk service API, run data, and shared utilities

---

## Commands

| Command | Alias | Description |
|---|---|---|
| `/eb` | — | Toggle the EbonBuilds main window |

---

## Saved Variables

`EbonBuildsDB` — persisted per-account:
- `builds` — all saved builds
- `activeBuildId` — currently active build
- `sessions` — session history logs
- `currentSessionIndex` — active session tracking
- `pendingWeights` — weights entered before the first build is saved
- `minimapAngle` — minimap button position
