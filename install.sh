#!/usr/bin/env bash
# Install platform-skills integrations from a local clone.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$PWD"
INSTALL_CLAUDE=0
INSTALL_CODEX=0
INSTALL_CURSOR=0
INSTALL_COPILOT=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Install platform-skills integrations from this local clone.

Options:
  --all                 Install Claude, Codex, Cursor, and Copilot integrations
  --claude              Install as a Claude plugin when the claude CLI is available
  --codex               Link this repo into ${CODEX_HOME:-$HOME/.codex}/skills
  --cursor              Copy Cursor rules into the target project
  --copilot             Copy GitHub Copilot instructions into the target project
  --target PATH         Project path for Cursor and Copilot files (default: current directory)
  -h, --help            Show this help

Examples:
  ./install.sh --codex
  ./install.sh --cursor --copilot --target ../your-project
  ./install.sh --all --target ../your-project
EOF
}

log() {
  printf '==> %s\n' "$1"
}

backup_if_changed() {
  local src="$1"
  local dest="$2"

  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "${dest}.bak"
    log "Backed up existing ${dest#$TARGET_DIR/} to ${dest#$TARGET_DIR/}.bak"
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  backup_if_changed "$src" "$dest"
  cp "$src" "$dest"
  log "Installed ${dest#$TARGET_DIR/}"
}

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    log "Installing Claude plugin from $ROOT_DIR"
    claude plugin install "$ROOT_DIR"
  else
    cat <<EOF
Claude CLI not found. Install manually after setting up Claude Code:

  claude plugin marketplace add https://github.com/nitinjain999/platform-skills
  claude plugin install platform-skills

Or from this local clone:

  claude plugin install "$ROOT_DIR"
EOF
  fi
}

install_codex() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local skills_dir="$codex_home/skills"
  local dest="$skills_dir/platform-skills"

  mkdir -p "$skills_dir"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    cat <<EOF
Codex skill path already exists and is not a symlink:
  $dest

Leaving it in place. To use this clone, move the existing directory aside and rerun:
  ./install.sh --codex
EOF
    return 0
  fi

  ln -sfn "$ROOT_DIR" "$dest"
  log "Linked Codex skill at $dest"
}

install_cursor() {
  copy_file "$ROOT_DIR/.cursorrules" "$TARGET_DIR/.cursorrules"
  mkdir -p "$TARGET_DIR/.cursor/rules"

  local rule
  for rule in "$ROOT_DIR"/.cursor/rules/*.mdc; do
    copy_file "$rule" "$TARGET_DIR/.cursor/rules/$(basename "$rule")"
  done
}

install_copilot() {
  copy_file "$ROOT_DIR/.github/copilot-instructions.md" "$TARGET_DIR/.github/copilot-instructions.md"
}

if [ "$#" -eq 0 ]; then
  usage
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      INSTALL_CLAUDE=1
      INSTALL_CODEX=1
      INSTALL_CURSOR=1
      INSTALL_COPILOT=1
      ;;
    --claude)
      INSTALL_CLAUDE=1
      ;;
    --codex)
      INSTALL_CODEX=1
      ;;
    --cursor)
      INSTALL_CURSOR=1
      ;;
    --copilot)
      INSTALL_COPILOT=1
      ;;
    --target)
      if [ "${2:-}" = "" ]; then
        echo "ERROR: --target requires a path" >&2
        exit 2
      fi
      if [ ! -d "$2" ]; then
        echo "ERROR: --target directory does not exist: $2" >&2
        exit 2
      fi
      TARGET_DIR="$(cd "$2" && pwd)"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$INSTALL_CLAUDE" -eq 0 ] && [ "$INSTALL_CODEX" -eq 0 ] && [ "$INSTALL_CURSOR" -eq 0 ] && [ "$INSTALL_COPILOT" -eq 0 ]; then
  usage
  exit 0
fi

[ "$INSTALL_CLAUDE" -eq 1 ] && install_claude
[ "$INSTALL_CODEX" -eq 1 ] && install_codex
[ "$INSTALL_CURSOR" -eq 1 ] && install_cursor
[ "$INSTALL_COPILOT" -eq 1 ] && install_copilot

cat <<EOF

Done.

Try:
  Use \$platform-skills to review this Terraform change for ownership, blast radius, validation, and rollback.
EOF
