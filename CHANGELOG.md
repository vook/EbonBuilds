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
