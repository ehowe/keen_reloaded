#!/bin/sh
# tools/changelog.sh — generate markdown changelog section from conventional commits.
# Usage: changelog.sh <since-ref> <version>
#   since-ref: previous git tag/ref to start from. Empty = full history.
#   version:   version string for the section header.
# Outputs a "## v<version> — <date>" section to stdout.

set -eu

since="${1:-}"
version="${2:-unknown}"
today=$(date +%Y-%m-%d)

if [ -n "$since" ]; then
    git log --format='%s' "${since}..HEAD" 2>/dev/null
else
    git log --format='%s' 2>/dev/null
fi | awk -v header="## v${version} — ${today}" '
    BEGIN {
        order_n = 5
        order[1] = "Added"
        order[2] = "Fixed"
        order[3] = "Performance"
        order[4] = "Documentation"
        order[5] = "Refactored"
        map["feat"] = "Added"
        map["fix"] = "Fixed"
        map["perf"] = "Performance"
        map["docs"] = "Documentation"
        map["refactor"] = "Refactored"
        any = 0
    }
    {
        line = $0
        if (match(line, /^[a-z]+(\([^)]*\))?!?:/)) {
            prefix = substr(line, 1, RLENGTH)
            rest = substr(line, RLENGTH + 1)
            sub(/^ +/, "", rest)
            type = prefix
            sub(/\(.*/, "", type)
            sub(/!.*/, "", type)
            sub(/:$/, "", type)
            if (type in map) {
                h = map[type]
                key = h SUBSEP rest
                if (!(key in dedup)) {
                    dedup[key] = 1
                    entries[h] = entries[h] "- " rest "\n"
                    any = 1
                }
            }
        }
    }
    END {
        print header
        print ""
        if (!any) {
            print "_No notable changes._"
            print ""
        } else {
            for (i = 1; i <= order_n; i++) {
                h = order[i]
                if (h in entries) {
                    print "### " h
                    printf "%s", entries[h]
                    print ""
                }
            }
        }
    }
'
