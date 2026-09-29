#!/usr/bin/env bash
set -euo pipefail

DEV="${1:-/dev/video0}"

# Strictly validate device path
if [[ ! "$DEV" =~ ^/dev/video[0-9]+$ ]]; then
  exit 1
fi

# Producer-side bounds:
# 1. /usr/bin/timeout bounds execution to a 2-second deadline with 0.5s SIGKILL grace
# 2. /usr/bin/head -c 32768 caps stdout to at most 32 KiB; head exits on limit and SIGPIPE terminates the producer
exec /usr/bin/timeout -k 0.5s 2s /usr/bin/v4l2-ctl -d "$DEV" -l | /usr/bin/head -c 32768
