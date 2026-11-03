#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${IEB_SSH_TARGET:?Set IEB_SSH_TARGET to user@host}"
: "${IEB_SSH_IDENTITY:?Set IEB_SSH_IDENTITY to an existing private key path}"
IEB_SSH_PORT=${IEB_SSH_PORT:-22}
case "$IEB_SSH_TARGET" in -*|*[!a-zA-Z0-9_.@:-]*|'') echo 'Invalid SSH target' >&2; exit 64;; esac
case "$IEB_SSH_PORT" in *[!0-9]*|'') echo 'Invalid SSH port' >&2; exit 64;; esac
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != '--query' ] && [ "$1" != '--producer-query' ] && [ "$1" != '--producer-matrix' ]; }; then
    echo 'Usage: tools/run-device-probe.sh [--query|--producer-query|--producer-matrix]' >&2
    exit 64
fi
tools/build-probe.sh
command -v ldid >/dev/null 2>&1 || { echo 'ldid is required to sign the device probe' >&2; exit 69; }
scp -O -i "$IEB_SSH_IDENTITY" -P "$IEB_SSH_PORT" -o IdentitiesOnly=yes \
    -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=8 \
    .build/ieb-probe "$IEB_SSH_TARGET:/var/mobile/ieb-probe"
probe_command='/var/mobile/ieb-probe'
if [ "$#" -eq 1 ]; then
    case "$1" in
        --query) probe_command='/var/mobile/ieb-probe --query' ;;
        --producer-query) probe_command='/var/mobile/ieb-probe --producer-query' ;;
        --producer-matrix) probe_command='/var/mobile/ieb-probe --producer-matrix' ;;
    esac
fi
ssh -i "$IEB_SSH_IDENTITY" -p "$IEB_SSH_PORT" -o IdentitiesOnly=yes \
    -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=8 \
    "$IEB_SSH_TARGET" "$probe_command"
