# Changelog

All notable changes to EbonBuilds are documented in this file.

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
