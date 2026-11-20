#!/usr/bin/env bash
# Install or remove llm_map. It touches only two paths and never settings.json.
#   ~/.claude/hooks/llm_map.py
#   ~/.claude/skills/llm-map/SKILL.md
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
LM_DST="$HOOKS_DIR/llm_map.py"
SK_DIR="$HOME/.claude/skills/llm-map"
SK_DST="$SK_DIR/SKILL.md"
# Same marker line as the lossless-handoff installer, so an old copy counts as ours.
SK_MARK="<!-- lossless-handoff:llm-map-skill -->"
DRY=0
UNINSTALL=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [--dry-run] [--uninstall]

Installs llm_map.py to ~/.claude/hooks/llm_map.py and the skill to
~/.claude/skills/llm-map/SKILL.md. It does not change settings.json.
A file that it replaces is first copied to a backup folder.
--dry-run    show what would change, change nothing
--uninstall  remove llm_map.py and the skill (only a skill with our marker line)
USAGE
}

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $a" >&2; usage >&2; exit 2 ;;
  esac
done

say() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOOKS_DIR/.llm-map-backup-$STAMP"

backup() { # backup FILE: copy FILE into the backup folder
  say "backup: $1 -> $BACKUP/"
  if [ "$DRY" = 0 ]; then mkdir -p "$BACKUP"; cp -p "$1" "$BACKUP/$(basename "$(dirname "$1")")-$(basename "$1")"; fi
}

is_ours_skill() { grep -qF "$SK_MARK" "$1" 2>/dev/null; }

if [ "$UNINSTALL" = 1 ]; then
  if [ -e "$LM_DST" ]; then
    say "remove: $LM_DST"
    [ "$DRY" = 1 ] || rm -f "$LM_DST"
  else
    say "not installed: $LM_DST"
  fi
  if [ -e "$SK_DST" ] && is_ours_skill "$SK_DST"; then
    say "remove: $SK_DST"
    if [ "$DRY" = 0 ]; then rm -f "$SK_DST"; rmdir "$SK_DIR" 2>/dev/null || true; fi
  elif [ -e "$SK_DST" ]; then
    # shellcheck disable=SC2088  # print the literal ~ path for the user
    echo "~/.claude/skills/llm-map/SKILL.md exists and is not ours; left unchanged."
  else
    say "not installed: $SK_DST"
  fi
  exit 0
fi

[ -f "$SRC/llm_map.py" ] || { echo "llm_map.py is missing from $SRC" >&2; exit 1; }
[ -f "$SRC/skill/SKILL.md" ] || { echo "skill/SKILL.md is missing from $SRC" >&2; exit 1; }

if [ -f "$LM_DST" ] && cmp -s "$SRC/llm_map.py" "$LM_DST"; then
  say "unchanged: $LM_DST"
else
  [ ! -e "$LM_DST" ] || backup "$LM_DST"
  say "install: $LM_DST"
  if [ "$DRY" = 0 ]; then mkdir -p "$HOOKS_DIR"; cp "$SRC/llm_map.py" "$LM_DST"; chmod 755 "$LM_DST"; fi
fi

if [ -e "$SK_DST" ] && ! is_ours_skill "$SK_DST"; then
  # shellcheck disable=SC2088  # print the literal ~ path for the user
  echo "~/.claude/skills/llm-map/SKILL.md exists and is not ours; left unchanged."
elif [ -f "$SK_DST" ] && cmp -s "$SRC/skill/SKILL.md" "$SK_DST"; then
  say "unchanged: $SK_DST"
else
  [ ! -e "$SK_DST" ] || backup "$SK_DST"
  say "install: $SK_DST"
  if [ "$DRY" = 0 ]; then mkdir -p "$SK_DIR"; cp "$SRC/skill/SKILL.md" "$SK_DST"; chmod 644 "$SK_DST"; fi
fi
