#!/bin/bash
# Move a package to another upstream commit (default: the head of master).
#
#   ./bump.sh <package> [commit]
#
# Updates arch/<package>/PKGBUILD (_commit, _date, pkgrel=1, sha256sums[0])
# and fedora/<package>/{<package>.spec,sources} (commit, date, Release 1,
# a %changelog entry, the tarball checksum).  The version is
# 3.3.8b+git<YYYYMMDD>, the committer date (UTC) of the commit.  pkgrel and
# Release go back to 1, except when the new commit has the same date as the
# old one: then they are incremented, so that the new package still sorts
# as newer.
#
# Needs curl, python3, sha256sum and gh (if logged in) or plain access to
# api.github.com.

set -euo pipefail

top=$(cd "$(dirname "$0")" && pwd)
pkg=${1:?usage: $0 <package> [commit]}
ref=${2:-master}

declare -A repo=([kde3-qt]=kde3-revival/kde3-qt)
r=${repo[$pkg]:-}
[[ -n $r ]] || { echo "unknown package $pkg" >&2; exit 1; }

api() {
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
        gh api "$1"
    else
        curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"
    fi
}

read -r commit when < <(api "repos/$r/commits/$ref" | python3 -c '
import json, sys
c = json.load(sys.stdin)
print(c["sha"], c["commit"]["committer"]["date"])')
[[ $commit =~ ^[0-9a-f]{40}$ && -n $when ]] || { echo "could not parse the GitHub API answer" >&2; exit 1; }
date=$(date -u -d "$when" +%Y%m%d)
echo "$pkg: $commit ($when) -> 3.3.8b+git$date"

pb=$top/arch/$pkg/PKGBUILD
spec=$top/fedora/$pkg/$pkg.spec
old_commit=$(sed -n 's/^_commit=//p' "$pb")
old_date=$(sed -n 's/^_date=//p' "$pb")
if [[ $old_commit == "$commit" ]]; then
    echo "already at $commit"; exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tarball=$pkg-$commit.tar.gz
curl -fsSL -o "$tmp/$tarball" "https://github.com/$r/archive/$commit.tar.gz"
sum=$(sha256sum "$tmp/$tarball" | cut -d' ' -f1)
echo "sha256 $sum"

# Arch
if [[ $old_date == "$date" ]]; then
    rel=$(( $(sed -n 's/^pkgrel=//p' "$pb") + 1 ))
    frel=$(( $(sed -n 's/^Release: *\([0-9]*\).*/\1/p' "$spec") + 1 ))
else
    rel=1 frel=1
fi
sed -i -e "s/^_commit=.*/_commit=$commit/" \
       -e "s/^_date=.*/_date=$date/" \
       -e "s/^pkgrel=.*/pkgrel=$rel/" \
       -e "/^sha256sums=(/s/'[0-9a-f]\{64\}'/'$sum'/" "$pb"

# Fedora
entry="* $(LC_ALL=C date +'%a %b %d %Y') $(git -C "$top" config user.name) <$(git -C "$top" config user.email)> - 3.3.8b+git$date-$frel\n- Snapshot of $r commit ${commit:0:7}\n"
sed -i -e "s/^\(%global commit *\).*/\1$commit/" \
       -e "s/^\(%global date *\).*/\1$date/" \
       -e "s/^\(Release: *\)[0-9]*/\1$frel/" \
       -e "/^%changelog/a $entry" "$spec"
echo "SHA256 ($tarball) = $sum" >"$top/fedora/$pkg/sources"

git -C "$top" --no-pager diff --stat
