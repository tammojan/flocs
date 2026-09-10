#!/usr/bin/env bash
set -e

if [[ -f "${INSTALLDIR:-/opt/lofar}/init.sh" ]]; then
    # shellcheck disable=SC1090
    source "${INSTALLDIR:-/opt/lofar}/init.sh"
fi

exec "$@"
