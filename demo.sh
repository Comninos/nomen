#!/usr/bin/env bash
# Build a chunky fixture tree and print a nomen dry-run plan.
#   ./demo.sh           # uses /tmp/nomen-demo
#   ./demo.sh /path     # custom dir
set -euo pipefail

ROOT="${1:-/tmp/nomen-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOMEN="${SCRIPT_DIR}/nomen.sh"
if [[ ! -x "$NOMEN" ]]; then
    NOMEN="$(command -v nomen || true)"
fi
[[ -n "${NOMEN:-}" && -x "$NOMEN" ]] || {
    printf 'demo: need ./nomen.sh or nomen on PATH\n' >&2
    exit 1
}

rm -rf "$ROOT"
mkdir -p "$ROOT"/{inbox,photos/europe,archive,collide}

# Messy → rename
touch \
  "$ROOT/My Tax Receipt 2025.PDF" \
  "$ROOT/Q3_Budget_Final_V2.xlsx" \
  "$ROOT/Meeting Notes (Draft).md" \
  "$ROOT/TODO List!!!.txt" \
  "$ROOT/Scan_0012.PNG" \
  "$ROOT/IMG_0042.JPG" \
  "$ROOT/DSC09876.NEF" \
  "$ROOT/Holiday Europe Roadtrip 01.jpg" \
  "$ROOT/Holiday Europe Roadtrip 2.jpg" \
  "$ROOT/Holiday Europe Roadtrip 3.jpg" \
  "$ROOT/3D_Drone_Frame_v02.STEP" \
  "$ROOT/Linux Kernel Guide REF.pdf" \
  "$ROOT/26 Ref Notes MIXED Case.PDF" \
  "$ROOT/2608 Project Brief V0.1.2.md" \
  "$ROOT/Contract_Signed_V01.docx" \
  "$ROOT/fooBarBaz_utility.py" \
  "$ROOT/camelCaseReport.PDF" \
  "$ROOT/spaces   and___underscores.txt" \
  "$ROOT/260812taxes.pdf" \
  "$ROOT/reportv01.txt" \
  "$ROOT/v1.2.3-release.tar" \
  "$ROOT/2024-01-15-notes.md" \
  "$ROOT/Café Menu.pdf" \
  "$ROOT/release.tar.gz" \
  "$ROOT/inbox/Bank Statement Aug.pdf" \
  "$ROOT/inbox/Invoice #4421.PDF" \
  "$ROOT/inbox/old_scan__copy (1).pdf" \
  "$ROOT/photos/europe/IMG 1001.JPG" \
  "$ROOT/photos/europe/IMG 1002.JPG" \
  "$ROOT/photos/europe/Sunset_Lisbon_V1.JPG" \
  "$ROOT/archive/README FIRST.txt" \
  "$ROOT/archive/Notes From 2024.md"

# Already conforming → skip
touch \
  "$ROOT/260812-taxes-2025-receipts-v01.pdf" \
  "$ROOT/260812-holidays-europe-roadtrip-001.jpg" \
  "$ROOT/2608-3d-drone-frame-v02.step" \
  "$ROOT/26-ref-linux-kernel-guide.pdf" \
  "$ROOT/already-good-name.txt" \
  "$ROOT/photos/europe/2609-lisbon-sunset-003.jpg"

# Collision: messy name would become an existing good name
touch \
  "$ROOT/collide/Foo Bar.txt" \
  "$ROOT/collide/foo-bar.txt"

count="$(find "$ROOT" -type f | wc -l)"
printf 'demo tree: %s (%d files)\n\n' "$ROOT" "$count"

printf '=== top level only (no recurse) ===\n\n'
COLOR=never "$NOMEN" "$ROOT" </dev/null || true

printf '\n=== full tree (all files) ===\n\n'
mapfile -d '' -t ALL < <(find "$ROOT" -type f -print0 | sort -z)
COLOR=never "$NOMEN" "${ALL[@]}" </dev/null || true

printf '\nInteractive (colour + prompts):\n  cd %s && nomen .\n' "$ROOT"
printf 'Apply without prompts:\n  APPLY=1 nomen %s\n' "$ROOT"
printf 'Force colour in a pipe:\n  COLOR=always nomen %s\n' "$ROOT"
