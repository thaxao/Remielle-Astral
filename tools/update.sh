#!/usr/bin/env bash
# Updates Remielle Astral to the newest release.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$dir/tools/install.sh" "$@"
