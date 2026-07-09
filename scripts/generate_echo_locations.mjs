#!/usr/bin/env node
/**
 * Regenerate modules/data/EchoLocations.lua and EchoSourceMeta.lua from
 * https://worldofechoes.pages.dev/assets/data/tomes.json
 *
 * Usage: node scripts/generate_echo_locations.mjs
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const API_URL = "https://worldofechoes.pages.dev/assets/data/tomes.json";
const LOCATIONS_OUT = path.join(ROOT, "modules/data/EchoLocations.lua");
const META_OUT = path.join(ROOT, "modules/data/EchoSourceMeta.lua");

const ZONE_REGION = {
  northrend: "northrend",
  kalimdor: "kalimdor",
  "eastern-kingdoms": "eastern_kingdoms",
  outland: "outland",
};

const RAID_PATTERNS = [
  { key: "icecrown_citadel", match: /icecrown citadel/i },
  { key: "trial_of_the_crusader", match: /trial of the crusader|icecrown - trial/i },
  { key: "naxxramas", match: /naxxramas/i },
  { key: "ulduar", match: /ulduar/i },
  { key: "onyxias_lair", match: /onyxia/i },
  { key: "obsidian_sanctum", match: /obsidian sanctum/i },
  { key: "eye_of_eternity", match: /eye of eternity/i },
  { key: "black_temple", match: /black temple/i },
  { key: "culling_of_stratholme", match: /culling of stratholme/i },
  { key: "scarlet_monastery", match: /scarlet monastery/i },
];

function luaEscape(str) {
  return str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function parseExistingLocations(luaText) {
  const map = new Map();
  const re = /\[(\d+)\]\s*=\s*"((?:\\.|[^"\\])*)"/g;
  let m;
  while ((m = re.exec(luaText))) {
    map.set(Number(m[1]), m[2].replace(/\\"/g, '"'));
  }
  return map;
}

function buildBossToGroupId(existing) {
  const bossMap = new Map();
  for (const [groupId, text] of existing) {
    const parts = text.split(/\s*\|\s*/);
    for (const part of parts) {
      const segs = part.split(" - ");
      const boss = segs[segs.length - 1]?.trim();
      if (boss) {
        const norm = boss.toLowerCase();
        if (!bossMap.has(norm)) bossMap.set(norm, groupId);
      }
    }
  }
  return bossMap;
}

function isRaidNotes(notes) {
  if (!notes) return false;
  const n = notes.toLowerCase();
  return n === "raid" || n.includes("source: raid");
}

function isOpenWorldNotes(notes) {
  if (!notes) return false;
  const n = notes.toLowerCase();
  return n.includes("open world") && !n.includes("dungeon");
}

function detectRaid(text) {
  for (const p of RAID_PATTERNS) {
    if (p.match.test(text)) return p.key;
  }
  return null;
}

function formatLocation(loc) {
  const place = (loc.placeName || "").trim();
  const mobs = (loc.mobs || []).filter(Boolean).join(", ");
  if (place && mobs) return `${place} - ${mobs}`;
  return place || mobs || "Unknown";
}

function classifyLocation(loc, display) {
  const notes = loc.notes || "";
  const zone = loc.zone || "";
  const region = ZONE_REGION[zone] || null;
  const blob = `${display} ${notes} ${loc.placeName || ""}`;

  if (isRaidNotes(notes)) {
    const raid = detectRaid(blob) || detectRaid(loc.placeName || "");
    return { kind: "raid", region: "northrend", raid: raid || "unknown_raid" };
  }

  const raidFromPlace = detectRaid(blob);
  if (raidFromPlace && !isOpenWorldNotes(notes)) {
    return { kind: "raid", region: region || "northrend", raid: raidFromPlace };
  }

  if (region) {
    return { kind: "open_world", region, raid: null };
  }

  return { kind: "unknown", region: null, raid: null };
}

function findGroupId(loc, display, bossMap, existing) {
  for (const mob of loc.mobs || []) {
    const norm = mob.toLowerCase().trim();
    if (bossMap.has(norm)) return bossMap.get(norm);
    // partial boss match (e.g. "Icehowl" in longer name)
    for (const [boss, gid] of bossMap) {
      if (norm.includes(boss) || boss.includes(norm)) return gid;
    }
  }

  for (const [gid, text] of existing) {
    if (text === display) return gid;
    const place = (loc.placeName || "").trim();
    if (place && text.includes(place)) {
      for (const mob of loc.mobs || []) {
        if (text.toLowerCase().includes(mob.toLowerCase())) return gid;
      }
    }
  }

  return null;
}

async function main() {
  const existingText = fs.readFileSync(LOCATIONS_OUT, "utf8");
  const existing = parseExistingLocations(existingText);
  const bossMap = buildBossToGroupId(existing);

  const res = await fetch(API_URL);
  if (!res.ok) throw new Error(`Failed to fetch ${API_URL}: ${res.status}`);
  const data = await res.json();

  const tomeById = new Map((data.tomes || []).map((t) => [t.id, t]));
  const byGroup = new Map();

  for (const loc of data.locations || []) {
    const display = formatLocation(loc);
    const groupId = findGroupId(loc, display, bossMap, existing);
    if (!groupId) continue;

    const meta = classifyLocation(loc, display);
    if (!byGroup.has(groupId)) {
      byGroup.set(groupId, { displays: [], meta, tomeIds: new Set() });
    }
    const entry = byGroup.get(groupId);
    if (!entry.displays.includes(display)) entry.displays.push(display);
    entry.tomeIds.add(loc.tomeId);
    // Prefer raid classification when any location is a raid drop.
    if (meta.kind === "raid") entry.meta = meta;
  }

  // Preserve existing entries not matched from API (e.g. future ICC until WoE adds them).
  for (const [gid, text] of existing) {
    if (!byGroup.has(gid)) {
      const meta = { kind: "unknown", region: null, raid: null };
      const raid = detectRaid(text);
      if (raid) {
        meta.kind = "raid";
        meta.raid = raid;
        meta.region = "northrend";
      } else if (/outland|hellfire|nagrand|zangarmarsh|terokkar|blade|netherstorm|shadowmoon|bash'ir/i.test(text)) {
        meta.kind = "open_world";
        meta.region = "outland";
      } else if (/kalimdor|durotar|barrens|feralas|tanaris|ungoro|silithus|winterspring|ashenvale|darkshore|moonglade|dustwallow/i.test(text)) {
        meta.kind = "open_world";
        meta.region = "kalimdor";
      } else if (/northrend|icecrown|wintergrasp|crystalsong|dragonblight|zul'drak|borean|storm peaks|grizzly|sholazar|howling/i.test(text)) {
        meta.kind = "open_world";
        meta.region = "northrend";
      } else {
        meta.kind = "open_world";
        meta.region = "eastern_kingdoms";
      }
      byGroup.set(gid, { displays: [text], meta, tomeIds: new Set() });
    }
  }

  const groupIds = [...byGroup.keys()].sort((a, b) => a - b);

  const locLines = [
    "-- EbonBuilds: modules/data/EchoLocations.lua",
    "-- Responsibility: echo tome farming locations (place + mob), keyed by perk",
    "-- groupId. Sourced from the community World of Echoes map",
    "-- (https://worldofechoes.pages.dev/assets/data/tomes.json). Consumed by",
    "-- BuildOverview's Source column. Auto-generated; prefer regenerating over hand-editing.",
    "-- Generator: node scripts/generate_echo_locations.mjs",
    "",
    "EbonBuilds = EbonBuilds or {}",
    "",
    "EbonBuilds.EchoLocations = {",
  ];

  const metaLines = [
    "-- EbonBuilds: modules/data/EchoSourceMeta.lua",
    "-- Per-groupId source classification for Collection filters.",
    "-- Auto-generated by scripts/generate_echo_locations.mjs",
    "",
    "EbonBuilds = EbonBuilds or {}",
    "",
    "EbonBuilds.EchoSourceMeta = {",
  ];

  for (const gid of groupIds) {
    const { displays, meta } = byGroup.get(gid);
    const text = displays.join(" | ");
    locLines.push(`    [${gid}] = "${luaEscape(text)}",`);
    const raidVal = meta.raid ? `"${meta.raid}"` : "nil";
    const regionVal = meta.region ? `"${meta.region}"` : "nil";
    metaLines.push(
      `    [${gid}] = { kind = "${meta.kind}", region = ${regionVal}, raid = ${raidVal} },`,
    );
  }

  locLines.push("}", "");
  metaLines.push("}", "");

  fs.writeFileSync(LOCATIONS_OUT, locLines.join("\n"), "utf8");
  fs.writeFileSync(META_OUT, metaLines.join("\n"), "utf8");

  console.log(`Wrote ${groupIds.length} group entries to:`);
  console.log(`  ${LOCATIONS_OUT}`);
  console.log(`  ${META_OUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
