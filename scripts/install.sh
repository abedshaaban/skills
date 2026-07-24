#!/usr/bin/env bash
# install.sh — offline/local installer: copy a skill from this repo into a
# target project. Prefer `npx skills@latest add abedshaaban/skills` for the
# normal path; this is the no-network / hacking-on-the-repo fallback.
#
# Usage:
#   scripts/install.sh <skill> [target-project-dir] [--dir <skills-subdir>] [--symlink] [--force]
#   scripts/install.sh --list
#
#   <skill>              Skill to install: un-mcp | trello  (or "all")
#   target-project-dir   Project to install into. Default: current directory.
#   --dir <subdir>       Skills location inside the target. Default: .agents/skills
#                        (use ".claude/skills" for Claude Code projects).
#   --symlink            Symlink the skill instead of copying (edits track this repo).
#   --force              Overwrite an existing skill of the same name.
#   --list               List skills available in this repo and exit.
#
# Examples:
#   scripts/install.sh trello ~/code/myapp
#   scripts/install.sh un-mcp ~/code/myapp --dir .claude/skills
#   scripts/install.sh all . --symlink
set -euo pipefail

# Repo root is one level up from scripts/; skills live under skills/.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$REPO/skills"

# Skills = dirs under skills/ that contain a SKILL.md.
available() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    [[ -f "$d/SKILL.md" ]] && basename "$d"
  done
}

if [[ "${1:-}" == "--list" || "${1:-}" == "" ]]; then
  echo "Skills available in this repo:"
  while read -r s; do
    desc="$(sed -n 's/^description: //p' "$SKILLS_DIR/$s/SKILL.md" | head -c 100)"
    printf '  %-10s %s...\n' "$s" "$desc"
  done < <(available)
  echo
  echo "Install: scripts/install.sh <skill> [target-project-dir] [--dir <subdir>] [--symlink] [--force]"
  exit 0
fi

SKILL="$1"; shift
TARGET="."
SUBDIR=".agents/skills"
MODE="copy"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     SUBDIR="${2:?--dir needs a value}"; shift 2 ;;
    --symlink) MODE="symlink"; shift ;;
    --force)   FORCE=1; shift ;;
    --*)       echo "Unknown flag: $1" >&2; exit 1 ;;
    *)         TARGET="$1"; shift ;;
  esac
done

# Resolve which skills to install.
ALL=()
while IFS= read -r _s; do ALL+=("$_s"); done < <(available)
if [[ "$SKILL" == "all" ]]; then
  SKILLS=("${ALL[@]}")
else
  if ! printf '%s\n' "${ALL[@]}" | grep -qx "$SKILL"; then
    echo "No such skill: $SKILL" >&2
    echo "Available: ${ALL[*]}" >&2
    exit 1
  fi
  SKILLS=("$SKILL")
fi

DEST="$TARGET/$SUBDIR"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"   # absolute, needed for symlinks

for s in "${SKILLS[@]}"; do
  src="$SKILLS_DIR/$s"
  dst="$DEST/$s"
  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$dst"
    else
      echo "skip $s — already exists at $dst (use --force to overwrite)" >&2
      continue
    fi
  fi
  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$src" "$dst"
    echo "linked $s -> $dst"
  else
    cp -R "$src" "$dst"
    echo "copied $s -> $dst"
  fi
done

echo
echo "Done. Next: open each skill's SETUP.md and fill the project-root .env with credentials."
