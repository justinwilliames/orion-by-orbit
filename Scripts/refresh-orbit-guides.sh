#!/bin/bash
#
# Refresh the bundled Orbit guides corpus.
#
# Orion ships with a snapshot of the live Orbit guides export so it
# can ground answers in actual guide content offline. When new guides
# go live or existing guides get edited, run this script to pull the
# latest payload and commit the result.
#
# Source of truth:
#   https://get.yourorbit.team/api/guides/export
#
# Output:
#   Orion/orbit-guides.json — bundled into the .app at build time,
#                                 read by OrbitGuidesCorpus.swift
#
# Usage:
#   ./Scripts/refresh-orbit-guides.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/Orion/orbit-guides.json"
URL="https://get.yourorbit.team/api/guides/export"

echo "Fetching $URL"
TMP="$(mktemp)"
curl -fsSL "$URL" -o "$TMP"

# Sanity check + strip noise-only fields. The live export stamps an
# `exportedAt` timestamp on every deploy, which would otherwise turn
# every site redeploy into a "diff" and trigger a no-op Orion
# release for users via Sparkle. The retrieval code never reads
# `exportedAt`, so dropping it here gives us a deterministic file
# whose hash only changes when actual guide content changes.
COUNT="$(python3 -c "import json,sys; d=json.load(open('$TMP')); print(d.get('count', 0))")"
if [[ "$COUNT" -lt 50 ]]; then
  echo "ERROR: export returned only $COUNT guides — refusing to overwrite. Inspect $TMP." >&2
  exit 1
fi

python3 - <<PY > "$DEST"
import json
d = json.load(open("$TMP"))
# Strip the redeploy-volatile timestamp so diffs reflect real content.
d.pop("exportedAt", None)
# Sort keys for deterministic output — guards against JSON key ordering
# changes between Node serialisations producing spurious diffs.
print(json.dumps(d, sort_keys=True, ensure_ascii=False))
PY
rm -f "$TMP"
SIZE_KB="$(du -k "$DEST" | cut -f1)"
echo "Wrote $DEST — $COUNT guides, ${SIZE_KB} KB"
echo
echo "Next: commit the change and tag a release."
