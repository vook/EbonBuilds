# Changelog

All notable changes to EbonBuilds are documented in this file.

## [Unreleased]

### Compatibility
- EbonBuilds now works with both the server ProjectEbonhold addon and Project Ebonhold Enhanced. The hard TOC dependency was replaced with optional deps only (no LoadWith), and bootstrap waits for whichever backend exposes `_G.ProjectEbonhold`.

## [1.4.0] - 2026-07-09

### Stats tracking
- Wire `echoesSeen`, `qualityPicks`, `mostPicked`, `mostBanned`, and `runsCompleted`/`runsReset` counters through automation and session events.
- Overview Stats tab refreshes live when counters change.

### Per-quality echo weights
- Echo weights can be overridden per quality tier (Common through Legendary) using backward-compatible `\0Q` keys.
- Echoes editor table groups echoes with expandable per-quality sub-rows.
- Scoring and automation respect quality-specific overrides via `LookupWeight`.

### Tome owned column
- Echoes weight table shows whether each echo is learned on your account (tome owned).
- Shared column layout extracted to `EchoTableColumns` for consistent headers.

### Echo policies
- Per-echo automation policies: Normal, Ban 1st seen, Ban after pick, Ignore after pick, Never pick.
- Policy dropdown in the echoes editor; legacy `noveltyBanishList` migrates automatically.
- Automation scoring and selection honor policy flags.
- Auto-reroll triggers when the sum of all offered echo scores falls below the auto-reroll threshold; **Reroll guard %** blocks rerolls when any single offer scores above the guard.

### Policies overview tab
- Dedicated **Policies** tab lists echoes with non-default policies for quick review and edits.

### Echoes overview tab (Collection)
- Overview dashboard tab **Collection** (formerly Missing) with rolled, tome, source, base weight, and score columns.
- Drop sources resolved via echo location data; tri-state filters for tome requirement, multi-rank, and all classes.
- Live refresh when perks are granted.

### Affixes
- Scan affixes from your gear or inspected players; store multiple sources per build.
- Affixes tab in the build editor and overview dashboard.
- Cheapest-apply preview and anvil integration hooks.
- Scanned affixes included in build export/import (additive; older imports unaffected).
- Apply-from-build opens the Enchanted Anvil when needed; anvil button restored below the title.

### Echo Journal
- Collection tab **Echo Journal** button opens the native `/echoes` UI with frame focus retries.

### Stability
- Restored manual echo selection and automation pick flow by removing automation `onEventReceived` registrations that could override native ProjectEbonhold perk event handlers.
- Echo Journal opener keeps EbonBuilds visible and attempts to raise the native `/echoes` frame.

### Locked echo slots
- Locked-echo UI supports up to 6 slots across build editor, overview, wizard, build list, and public builds cards.
- Locked-echo serialization/import/export paths now normalize slot arrays up to 6 entries.
- Locked-slot detection was hardened to avoid calling runtime perk APIs from hot scoring/automation paths.

### Performance
- Collection and echoes editor no longer refresh on `SPELLS_CHANGED` (legacy spellbook signal); refresh is gated to visible UI and periodic collection polling.
- Background `OnUpdate` handlers (affix apply button, public builds reload cooldown) skip work while their parent window is hidden.
- Removed eager peak-score recomputation on every level-up.

### Automation
- Skip auto-reroll on the first echo offer of each run (banish/freeze/pick still apply).

### Echo ownership
- Removed legacy spellbook/`IsSpellKnown` tome checks; owned column uses `echoDiscovery` and `cachedPerkCounts` only.

### Collection source filters
- Regenerated echo location data from the World of Echoes API (`assets/data/tomes.json`).
- Collection tab adds a **Sources** dropdown to filter by open-world region (Northrend, Kalimdor, Eastern Kingdoms, Outland) or raid (Naxxramas, Ulduar, Trial of the Crusader, Icecrown Citadel, Onyxia's Lair, and more).
- Source filter supports **All Open World**, **All Raids**, **No Tome Required**, **Unknown Source** (tomes with no resolved drop location), and **Clear all filters**.
- Source filter selections reset on `/reload` and relog (not saved across sessions).
- Icecrown Citadel echoes classify from native `PerkDropSources` text when not yet present on the community map.

### Logbook copy report
- Logbook **Export** exports the selected session's action log plus a run-start snapshot of peak score and all five automation thresholds (with absolute score cutoffs).
- Automation settings are stored per session for accurate auditing; older sessions without a snapshot show a best-effort fallback from the active build.
