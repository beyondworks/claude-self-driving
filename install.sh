#!/bin/bash
# Installs the self-driving skill into ~/.claude/skills/self-driving/.
# To test-install elsewhere, override HOME (e.g. HOME=/tmp/test bash install.sh).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills/self-driving"
for f in SKILL.md config.example.json; do
  [ -f "$SRC/$f" ] || { echo "Missing $f in package: $SRC" >&2; exit 1; }
done
mkdir -p "$HOME/.claude/skills"
# Stage files first so running this from inside the skill folder itself still works.
STAGE="$(mktemp -d)"
for f in SKILL.md config.example.json README.md LICENSE; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "$STAGE/"; done
[ -d "$SRC/tools" ] && cp -R "$SRC/tools" "$STAGE/tools"
SRC="$STAGE"
KEEP=""
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  [ -f "$DEST/config.json" ] && KEEP="$(mktemp)" && cp "$DEST/config.json" "$KEEP"
  # Keep the backup outside skills/ (inside it would load as a duplicate skill).
  mkdir -p "$HOME/.claude/skills-backup"
  BAK="$HOME/.claude/skills-backup/self-driving.bak-$(date +%Y%m%d-%H%M%S)"
  mv "$DEST" "$BAK"
  echo "Moved the existing skill to: $BAK"
fi
mkdir -p "$DEST"
cp "$SRC/SKILL.md" "$SRC/config.example.json" "$SRC/README.md" "$DEST/" 2>/dev/null || cp "$SRC/SKILL.md" "$SRC/config.example.json" "$DEST/"
[ -f "$SRC/LICENSE" ] && cp "$SRC/LICENSE" "$DEST/"
if [ -d "$SRC/tools" ]; then
  cp -R "$SRC/tools" "$DEST/tools"
  # Build the Claude app window tool (skipped with a note if the Xcode command line tools are missing)
  if command -v swiftc >/dev/null 2>&1; then
    swiftc -O "$DEST/tools/drive.swift" -o "$DEST/tools/drive" && echo "Built the drive tool: $DEST/tools/drive"
  else
    echo "swiftc not found, so the drive tool was not built (run xcode-select --install, then install again)."
  fi
fi
if [ -n "$KEEP" ]; then
  mv "$KEEP" "$DEST/config.json"; echo "Kept your existing config.json."
else
  cp "$DEST/config.example.json" "$DEST/config.json"; echo "Created config: $DEST/config.json"
fi
rm -rf "$STAGE"
echo "Installed: $DEST"
echo "Open a new Claude Code session and self-driving will appear in the skill list."
