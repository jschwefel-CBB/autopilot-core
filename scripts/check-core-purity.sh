#!/usr/bin/env bash
# Fails if any platform framework is imported anywhere in the AutopilotCore target.
set -euo pipefail
HITS=$(grep -rnE 'import (AppKit|ApplicationServices|CoreGraphics|ScreenCaptureKit|Cocoa|Quartz)' Sources/AutopilotCore/ || true)
if [ -n "$HITS" ]; then
  echo "ERROR: AutopilotCore must stay platform-agnostic. Found platform imports:" >&2
  echo "$HITS" >&2
  exit 1
fi
echo "AutopilotCore purity OK — no platform imports."
