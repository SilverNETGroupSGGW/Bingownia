#!/usr/bin/env bash
# Repeats the real-network PeerRoomService test, one fresh browser page per run.
# Usage: tool/run_network_tests.sh <runs> <guests> <toggles> [public|local] [logfile]
# "local" redirects 0.peerjs.com to a PeerServer on 127.0.0.1:9443 (see tool/chrome-headless-local-signalling.sh).
set -u
cd "$(dirname "$0")/.."
runs=${1:-5} guests=${2:-5} toggles=${3:-120} mode=${4:-public}
log=${5:-/tmp/bingownia-net-$mode-${guests}g.log}
if [ "$mode" = local ]; then
  export CHROME_EXECUTABLE=$PWD/tool/chrome-headless-local-signalling.sh
else
  export CHROME_EXECUTABLE=$PWD/tool/chrome-headless.sh
fi
: > "$log"
pass=0
for run in $(seq 1 "$runs"); do
  # shortcut: one page per run, because in one page the ~57th Peer's signalling socket never opened (not investigated).
  if timeout 180 flutter test test/network/peer_room_service_network_test.dart --platform chrome \
      --dart-define=RUNS=1 --dart-define=GUESTS="$guests" --dart-define=TOGGLES="$toggles" \
      2>&1 | grep -v 'available)' | sed "s/run=1 /run=$run /" >> "$log"; [ "${PIPESTATUS[0]}" = 0 ]; then
    pass=$((pass + 1))
  fi
done
echo "mode=$mode guests=$guests runs=$runs passed=$pass log=$log"
grep -E "FAIL|MISMATCH" "$log" || true
