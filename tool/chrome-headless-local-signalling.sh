#!/bin/sh
# Redirects the app's hard-coded signalling host (0.peerjs.com) to a local PeerServer on 127.0.0.1:9443.
exec "$(dirname "$0")/chrome-headless.sh" --host-resolver-rules="MAP 0.peerjs.com 127.0.0.1:9443" --ignore-certificate-errors "$@"
