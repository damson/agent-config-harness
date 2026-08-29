#!/usr/bin/env bash
#
# Detect the workspace domain for a given project path.
# Prints the domain name on stdout. Exits non-zero on no/ambiguous match.
#
# Usage:
#   ./bin/detect-domain.sh /path/to/project
#   domain=$(./bin/detect-domain.sh "$PWD") || exit 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

if [ $# -lt 1 ]; then
    log_error "Usage: $(basename "$0") <project_path>"
fi

detect_domain "$1"
