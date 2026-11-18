#!/usr/bin/env bash
# Build Debug app Mac của Xdesk.
set -euo pipefail
cd "$(dirname "$0")/.."
exec make build-mac
