#!/usr/bin/env bash
# install.sh — wire musecode into Claude Code on this machine with symlinks (idempotent).
#
#   ./install.sh            install / refresh symlinks, create ~/.config/muse-run/env if missing
#   ./install.sh --check    only report dependencies and host caps, change nothing
#   ./install.sh --uninstall
#
# Env overrides: MUSE_BIN_DIR (default ~/.local/bin), CLAUDE_DIR (default ~/.claude),
#                MUSE_RUN_ENV (default ~/.config/muse-run/env)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN_DIR=${MUSE_BIN_DIR:-$HOME/.local/bin}
CLAUDE_DIR=${CLAUDE_DIR:-$HOME/.claude}
ENV_FILE=${MUSE_RUN_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/muse-run/env}
MODE=${1:-install}

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
miss() { printf '  MISS  %s\n' "$*"; FAIL=1; }
FAIL=0

echo "Dependencies"
if command -v opencode >/dev/null 2>&1; then
  ok "opencode $(opencode --version 2>/dev/null | head -1)"
  if opencode models 2>/dev/null | grep -q '^opencode/muse-spark-1.3-contributor-free$'; then
    ok "model opencode/muse-spark-1.3-contributor-free is listed"
  else
    warn "opencode does not list opencode/muse-spark-1.3-contributor-free — run 'opencode models | grep muse' and set MUSE_MODEL in $ENV_FILE"
  fi
else
  miss "opencode (https://opencode.ai — 'npm i -g opencode-ai' or 'brew install sst/tap/opencode')"
fi
command -v jq >/dev/null 2>&1 && ok "jq" || miss "jq"
command -v claude >/dev/null 2>&1 && ok "claude $(claude --version 2>/dev/null | head -1)" || warn "claude not on PATH (Claude Code)"
if command -v setsid >/dev/null 2>&1; then ok "setsid (detached jobs)"
elif command -v perl >/dev/null 2>&1; then ok "perl (setsid fallback for detached jobs)"
else warn "neither setsid nor perl — jobs detach with plain nohup"; fi
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then ok "timeout (job wall clock)"
else warn "no timeout/gtimeout — using a bash watchdog (brew install coreutils gives gtimeout)"; fi

echo "Host"
if command -v nproc >/dev/null 2>&1; then CPUS=$(nproc); else CPUS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2); fi
CAP=$(( CPUS - 2 )); [ "$CAP" -lt 2 ] && CAP=2; [ "$CAP" -gt 16 ] && CAP=16
if [ -r /proc/meminfo ]; then
  TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
else
  TOTAL_MB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 ))
fi
printf '  cpus=%s  workflow concurrent-agent cap=min(16,max(2,cpus-2))=%s  ram=%s MB\n' "$CPUS" "$CAP" "$TOTAL_MB"
[ "$CAP" -le 2 ] && echo "  -> low cap: use the MUSE-START / MUSE-WAIT split for fan-outs wider than $CAP (see commands/musecode.md)"

[ "$MODE" = --check ] && exit $FAIL

if [ "$MODE" = --uninstall ]; then
  echo "Uninstall"
  for f in "$CLAUDE_DIR/agents/muse.md" "$CLAUDE_DIR/commands/musecode.md" "$BIN_DIR/muse-run"; do
    if [ -L "$f" ]; then rm "$f"; ok "removed $f"; else warn "not a symlink, left alone: $f"; fi
  done
  echo "  kept $ENV_FILE and ~/.cache/muse-run (delete by hand if you want)"
  exit 0
fi

echo "Install"
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$BIN_DIR" "$(dirname "$ENV_FILE")"
ln -sfn "$HERE/agents/muse.md"        "$CLAUDE_DIR/agents/muse.md"     && ok "$CLAUDE_DIR/agents/muse.md"
ln -sfn "$HERE/commands/musecode.md"  "$CLAUDE_DIR/commands/musecode.md" && ok "$CLAUDE_DIR/commands/musecode.md"
ln -sfn "$HERE/bin/muse-run"          "$BIN_DIR/muse-run"              && ok "$BIN_DIR/muse-run"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not on PATH — the relay agent runs 'muse-run' by name; add it to your shell rc" ;; esac
if [ -f "$ENV_FILE" ]; then
  ok "$ENV_FILE exists (kept)"
else
  cp "$HERE/env.example" "$ENV_FILE" && ok "$ENV_FILE created from env.example — uncomment a memory profile"
fi

echo
echo "Effective settings:"; "$HERE/bin/muse-run" --env | sed 's/^/  /'
echo
echo "Agent definitions load at Claude Code startup: start a NEW session, then try"
echo "  /musecode <task>      or      Agent({subagent_type: 'muse', prompt: '...'})"
echo "Smoke test without Claude:  muse-run 'Reply with exactly the word OK and nothing else'"
exit $FAIL
