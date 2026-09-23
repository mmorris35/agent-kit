#!/usr/bin/env bash
# agent-kit setup — Linux. Stands up Nellie locally and wires it into Claude Code.
#
# Safe to re-run: every step checks before it acts.
# Nellie binds to 127.0.0.1 by default, so nothing here is reachable from
# another machine unless you pass --bind and choose that.
#
# Usage:
#   ./setup.sh                 install and wire everything
#   ./setup.sh --check         report what is missing, change nothing
#   ./setup.sh --port 8765     port for the Nellie server (default 8765)
#   ./setup.sh --bind ADDR     address to serve on (default 127.0.0.1, this
#                              machine only). Use 0.0.0.0 or a LAN/tailnet
#                              address to share one memory across machines —
#                              Nellie has no auth of its own, so whoever can
#                              reach the port can read everything it knows.
#   ./setup.sh --watch DIR     directory Nellie indexes (default ~/projects)
#   ./setup.sh --src DIR       where to clone/build Nellie (default ~/src/nellie)
#   ./setup.sh --no-service    skip the systemd user service
#   ./setup.sh --skip-build    use an existing nellie binary, do not build

set -euo pipefail

PORT=8765
BIND="127.0.0.1"
WATCH_DIR="$HOME/projects"
SRC_DIR="$HOME/src/nellie"
CHECK_ONLY=false
NO_SERVICE=false
SKIP_BUILD=false
NELLIE_REPO="https://github.com/mmorris35/nellie.git"
BIN_DIR="$HOME/.local/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --port) PORT="${2:?--port needs a value}"; shift 2 ;;
    --bind) BIND="${2:?--bind needs a value}"; shift 2 ;;
    --watch) WATCH_DIR="${2:?--watch needs a value}"; shift 2 ;;
    --src) SRC_DIR="${2:?--src needs a value}"; shift 2 ;;
    --no-service) NO_SERVICE=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
note() { echo -e "${YELLOW}[--]${NC} $*"; }
die()  { echo -e "${RED}[!!]${NC} $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }

[[ $EUID -eq 0 ]] && die "run as your normal user, not root (it uses sudo only for apt)"

# Where to reach the server once it is up. A server bound to 0.0.0.0 still
# answers on loopback; one bound to a specific address only answers there.
if [[ "$BIND" == "0.0.0.0" || "$BIND" == "127.0.0.1" ]]; then
  REACH_HOST="127.0.0.1"
else
  REACH_HOST="$BIND"
fi
NELLIE_URL="http://${REACH_HOST}:${PORT}"

if [[ "$BIND" != "127.0.0.1" ]]; then
  echo "NOTE: serving on ${BIND}, not just this machine."
  echo "      Nellie has no authentication. Anything that can reach ${BIND}:${PORT}"
  echo "      can read every lesson, checkpoint and indexed file it holds."
  echo "      Put it on a network where that is acceptable, or bind 127.0.0.1."
  echo
fi

# ---------------------------------------------------------------- prerequisites
APT_PACKAGES=(build-essential pkg-config libssl-dev libclang-dev git curl)

check_prereqs() {
  local missing=()
  command -v claude >/dev/null || missing+=("claude (Claude Code CLI)")
  command -v git >/dev/null || missing+=("git")
  command -v curl >/dev/null || missing+=("curl")
  command -v cargo >/dev/null || missing+=("cargo (Rust toolchain)")
  command -v systemctl >/dev/null || missing+=("systemctl (systemd)")
  if [[ ${#missing[@]} -gt 0 ]]; then
    for m in "${missing[@]}"; do note "missing: $m"; done
    return 1
  fi
  return 0
}

if $CHECK_ONLY; then
  step "Checking prerequisites"
  if check_prereqs; then ok "everything needed is present"; else note "run ./setup.sh to install what is missing"; fi
  echo
  echo "bind:        $BIND"
  echo "port:        $PORT"
  echo "watch dir:   $WATCH_DIR"
  echo "nellie src:  $SRC_DIR"
  if command -v nellie >/dev/null; then
    ok "nellie binary: $(command -v nellie)"
  else
    note "nellie binary not installed yet"
  fi
  if curl -sf --max-time 2 "${NELLIE_URL}/health" >/dev/null 2>&1; then
    ok "a Nellie server is already answering on ${NELLIE_URL}"
  else
    note "nothing answering on ${NELLIE_URL} yet"
  fi
  exit 0
fi

step "Prerequisites"
command -v claude >/dev/null || die "Claude Code CLI not found. Install it first, then re-run: https://docs.claude.com/en/docs/claude-code"

if command -v apt-get >/dev/null; then
  MISSING_PKGS=()
  for p in "${APT_PACKAGES[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || MISSING_PKGS+=("$p")
  done
  if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    note "installing: ${MISSING_PKGS[*]} (sudo will prompt)"
    sudo apt-get update -qq
    sudo apt-get install -y "${MISSING_PKGS[@]}"
  fi
  ok "apt packages present"
else
  note "no apt-get here. Ensure these exist by other means: ${APT_PACKAGES[*]}"
fi

if ! command -v cargo >/dev/null; then
  note "installing Rust via rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi
export PATH="$HOME/.cargo/bin:$PATH"
ok "cargo: $(cargo --version)"

# ---------------------------------------------------------------------- build
step "Nellie"
if ! $SKIP_BUILD; then
  if [[ -d "$SRC_DIR/.git" ]]; then
    note "updating $SRC_DIR"
    git -C "$SRC_DIR" pull --ff-only
  else
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone "$NELLIE_REPO" "$SRC_DIR"
  fi
  note "building (first build takes a while)"
  ( cd "$SRC_DIR" && cargo build --release )
  mkdir -p "$BIN_DIR"
  ln -sf "$SRC_DIR/target/release/nellie" "$BIN_DIR/nellie"
fi

export PATH="$BIN_DIR:$PATH"
command -v nellie >/dev/null || die "nellie binary not on PATH. Expected $BIN_DIR/nellie"
ok "nellie: $(command -v nellie)"

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) note "add this to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# One-time: downloads the ONNX runtime and embedding model.
if [[ ! -d "$HOME/.local/share/nellie/models" ]]; then
  note "downloading embedding model (one time)"
  nellie setup
fi
ok "model present"
ORT_LIB="$HOME/.local/share/nellie/lib/libonnxruntime.so"
[[ -f "$ORT_LIB" ]] || die "ONNX Runtime missing at $ORT_LIB. Re-run: nellie setup"
ok "ONNX Runtime present"

mkdir -p "$WATCH_DIR"

# ---------------------------------------------------------------------- serve
step "Server"
if $NO_SERVICE; then
  note "skipping the service. Start Nellie yourself with:"
  echo "  ORT_DYLIB_PATH=~/.local/share/nellie/lib/libonnxruntime.so \\"
  echo "  nellie serve --host $BIND --port $PORT --data-dir ~/.local/share/nellie \\"
  echo "    --watch $WATCH_DIR --enable-graph --enable-structural --enable-deep-hooks --sync-interval 30"
else
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$UNIT_DIR"
  sed -e "s|__NELLIE_BIN__|$BIN_DIR/nellie|g" \
      -e "s|__BIND__|$BIND|g" \
      -e "s|__PORT__|$PORT|g" \
      -e "s|__DATA_DIR__|$HOME/.local/share/nellie|g" \
      -e "s|__WATCH_DIR__|$WATCH_DIR|g" \
      "$(dirname "$0")/systemd/nellie.service" > "$UNIT_DIR/nellie.service"
  systemctl --user daemon-reload
  systemctl --user enable --now nellie.service
  # Keeps the service running when nobody is logged in.
  loginctl enable-linger "$USER" 2>/dev/null || note "could not enable linger; Nellie stops when you log out"
  ok "service installed and started"
fi

note "waiting for ${NELLIE_URL}/health"
for _ in $(seq 1 60); do
  if curl -sf --max-time 2 "${NELLIE_URL}/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! curl -sf --max-time 2 "${NELLIE_URL}/health" >/dev/null 2>&1; then
  die "Nellie is not answering on ${NELLIE_URL}. Logs: journalctl --user -u nellie -n 50"
fi
ok "server healthy"

# ------------------------------------------------------------------ claude wiring
step "Claude Code"
if claude mcp list 2>/dev/null | grep -q '^nellie'; then
  ok "MCP server 'nellie' already registered"
else
  claude mcp add nellie --transport sse "${NELLIE_URL}/sse" --scope user
  ok "MCP server registered"
fi

# Installs SessionStart, Stop and UserPromptSubmit hooks. This is the part that
# makes sessions continuous: memory is loaded and saved without being asked.
nellie hooks-install --server "${NELLIE_URL}"
ok "hooks installed"

step "Verify"
nellie hooks-status || note "hooks-status reported a problem"
echo
nellie status 2>/dev/null || note "status unavailable"
echo
ok "done"
cat <<EOF

Next:
  1. Scaffold a project:   ./init-workspace.sh ~/projects/<your-project>
  2. Open Claude Code there and ask it to read CLAUDE.md.
  3. Check state any time: nellie hooks-status && curl -s ${NELLIE_URL}/health

Service:  systemctl --user status nellie
Logs:     journalctl --user -u nellie -f
EOF
