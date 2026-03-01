#!/usr/bin/env bash
set -e

# Terminate file: when this exists, the action exits and the workflow can finish
TERMINATE_FILE="${TERMINATE_FILE:-/tmp/terminate_debugging}"
PORT="${TTYD_PORT:-7681}"

# --- Detect architecture for static binaries ---
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)  TTYD_ARCH=x86_64;  TMUX_ARCH=x86_64;  NGROK_ARCH=amd64 ;;
  aarch64|arm64) TTYD_ARCH=aarch64; TMUX_ARCH=arm64;   NGROK_ARCH=arm64 ;;
  *) echo "::error::Unsupported arch: $ARCH"; exit 1 ;;
esac

BIN_DIR="${RUNNER_TEMP:-/tmp}/ttyd-debug-bins"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# --- Install ttyd (static) ---
TTYD_VER="1.7.7"
ttyd_url="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VER}/ttyd.${TTYD_ARCH}"
echo "::notice::Downloading ttyd (${TTYD_ARCH})..."
curl -sSL -o "$BIN_DIR/ttyd" "$ttyd_url"
chmod +x "$BIN_DIR/ttyd"

# --- Install tmux (static) ---
TMUX_VER="v3.6a"
tmux_url="https://github.com/pythops/tmux-linux-binary/releases/download/${TMUX_VER}/tmux-linux-${TMUX_ARCH}"
echo "::notice::Downloading tmux (${TMUX_ARCH})..."
curl -sSL -o "$BIN_DIR/tmux" "$tmux_url"
chmod +x "$BIN_DIR/tmux"

# --- Install ngrok ---
ngrok_tgz="${RUNNER_TEMP:-/tmp}/ngrok.tgz"
if [ "$NGROK_ARCH" = "amd64" ]; then
  ngrok_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
else
  ngrok_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
fi
echo "::notice::Downloading ngrok..."
curl -sSL -o "$ngrok_tgz" "$ngrok_url"
tar -xzf "$ngrok_tgz" -C "$BIN_DIR"
rm -f "$ngrok_tgz"

# --- Configure ngrok (never echo token) ---
if [ -n "$NGROK_AUTHTOKEN" ]; then
  ngrok config add-authtoken "$NGROK_AUTHTOKEN" 2>/dev/null || true
fi

# --- Start tmux session with explicit socket (so ttyd-spawned attach finds it) ---
# Use -d -m -s name -S path (not -dmS which parses as -S "debug" and overwrites the socket path)
TMUX_SOCK="${RUNNER_TEMP:-/tmp}/ttyd-debug-tmux.sock"
tmux -S "$TMUX_SOCK" new-session -d -s debug
sleep 1

# --- Start ttyd: attach to that session (-W = writable). Optional basic auth via -c user:pass ---
TTYD_EXTRA=()
if [ -n "${TTYD_PASSWORD:-}" ]; then
  TTYD_EXTRA=(-c "${TTYD_USERNAME:-debug}:${TTYD_PASSWORD}")
  echo "::notice title=Debug session::Basic auth enabled (username: ${TTYD_USERNAME:-debug})."
fi
ttyd -W -p "$PORT" -i 127.0.0.1 "${TTYD_EXTRA[@]}" tmux -S "$TMUX_SOCK" attach -t debug &
TTYD_PID=$!
sleep 1

# --- Start ngrok (background) ---
if [ -n "$NGROK_DOMAIN" ]; then
  ngrok http "$PORT" --domain="$NGROK_DOMAIN" --log=stdout &
else
  ngrok http "$PORT" --log=stdout &
fi
NGROK_PID=$!
sleep 3

# --- Get public URL from ngrok local API (no jq) ---
PUBLIC_URL=""
for _ in 1 2 3 4 5; do
  json=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null)
  PUBLIC_URL=$(echo "$json" | grep -oE '"public_url"[[:space:]]*:[[:space:]]*"https://[^"]+' | head -1 | sed 's/.*"https/https/; s/"$//')
  [ -n "$PUBLIC_URL" ] && break
  sleep 2
done

if [ -z "$PUBLIC_URL" ]; then
  echo "::error::Could not get ngrok URL. Check ngrok authtoken and logs."
  kill $TTYD_PID $NGROK_PID 2>/dev/null || true
  exit 1
fi

echo "::notice title=Debug session::Open in browser: $PUBLIC_URL"
echo "::notice title=To finish workflow::In the browser terminal run: touch $TERMINATE_FILE"

# --- Wait until user creates the terminate file ---
while [ ! -f "$TERMINATE_FILE" ]; do
  sleep 5
done

echo "::notice::Terminate file found. Exiting debug step."
kill $TTYD_PID $NGROK_PID 2>/dev/null || true
exit 0
