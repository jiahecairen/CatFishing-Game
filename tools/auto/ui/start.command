#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
echo "Fishing AUTO-002: $ROOT"
cd "$ROOT"
/usr/bin/env python3 tools/auto/ui/server.py --project "$ROOT"
