#!/usr/bin/env bash
# agent-kit init-workspace — put the memory scaffolding into a project.
#
# Copies the templates into a directory, never overwriting what is already
# there. Run it once per project you want an agent to work in.
#
# Usage: ./init-workspace.sh ~/projects/my-project

set -euo pipefail

TARGET="${1:-}"
[[ -n "$TARGET" ]] || { echo "usage: ./init-workspace.sh <project-dir>" >&2; exit 2; }

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES="$KIT_DIR/templates"
[[ -d "$TEMPLATES" ]] || { echo "templates/ not found next to this script" >&2; exit 1; }

mkdir -p "$TARGET"
cd "$TARGET"

copied=0
skipped=0

copy() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    echo "  kept    $dest (already exists)"
    skipped=$((skipped + 1))
  else
    cp "$src" "$dest"
    echo "  created $dest"
    copied=$((copied + 1))
  fi
}

echo "Scaffolding $TARGET"
copy "$TEMPLATES/CLAUDE.md"                  "CLAUDE.md"
copy "$TEMPLATES/purpose.md"                 "purpose.md"
copy "$TEMPLATES/memory/MEMORY.md"           "memory/MEMORY.md"
copy "$TEMPLATES/memory/working_summary.md"  "memory/working_summary.md"
copy "$TEMPLATES/memory/mistakes.md"         "memory/mistakes.md"
copy "$TEMPLATES/memory/open_questions.md"   "memory/open_questions.md"

echo
echo "$copied created, $skipped left alone."
cat <<'EOF'

Now, in that directory:
  1. Fill in purpose.md — what this project is for. Two paragraphs is plenty.
  2. Edit CLAUDE.md where it says EDIT ME (how you want to be talked to, and
     any project-specific commands).
  3. Start Claude Code there and tell it to read CLAUDE.md.

memory/ fills itself in as you work, if the Nellie hooks are installed.
EOF
