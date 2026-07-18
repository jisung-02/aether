#!/usr/bin/env bash
# Interop harness: start the Aether HTTP/3 example server and hit it with
# an HTTP/3-capable curl. Requires a curl built with HTTP/3 support
# (the macOS system curl is NOT — see the check below).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-4433}"
CURL="${CURL:-curl}"

if ! "$CURL" --version | grep -q HTTP3; then
  cat >&2 <<'EOF'
This curl has no HTTP/3 support. Install one, e.g.:

  macOS:  brew install curl        # then use /opt/homebrew/opt/curl/bin/curl
          CURL=/opt/homebrew/opt/curl/bin/curl ./interop/run.sh
  or build curl against ngtcp2/quiche (see https://curl.se/docs/http3.html)

You can also test with a browser: open https://localhost:4433/ (accept the
self-signed cert) with QUIC/HTTP3 enabled.
EOF
  exit 1
fi

echo "Building the example server..."
cd "$ROOT"
gleam build

echo "Starting Aether HTTP/3 server on :$PORT ..."
gleam run -m aether/examples/http3/server &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 2

echo "Requesting https://localhost:$PORT/ over HTTP/3 ..."
"$CURL" --http3-only -k -sS "https://localhost:$PORT/" -o - -w '\n[status %{http_code}, %{http_version}]\n'

echo "Done."
