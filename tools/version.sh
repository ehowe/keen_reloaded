#!/bin/sh
# tools/version.sh — compute the next release version (CalVer YYYY.MM.DD).
# Same-day re-releases get a trailing counter: .2, .3, ...
# Outputs the target version string to stdout.

set -eu

today=$(date +%Y.%m.%d)
current=$(cat VERSION 2>/dev/null || echo "0.0.0")

case "$current" in
    "$today".*)
        suffix=${current#"$today".}
        echo "${today}.$((suffix + 1))"
        ;;
    "$today")
        echo "${today}.2"
        ;;
    *)
        echo "$today"
        ;;
esac
