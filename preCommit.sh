#!/bin/bash
# pre-commit: run every pre-commit step, in order.
#
#     datestampHook.pl               schema.org dateModified on staged HTML
#     ntpStatHook.pl                 NTP unique-client figures on staged HTML
#     assetsBuild/makeFeed.py        Atom + RSS for /personal/blog.html
#     assetsBuild/makeMeta.py        blog.html's JSON-LD + sitemap.xml
#     assetsBuild/makeFontSubset.py  ubuntu804's DejaVu subsets
#     assetsBuild/badgeBuild.pl      the 88x31 wall: WebP + generated markup
#
# ADDING A STEP: put it below, and make it re-stage anything it rewrites.
# git runs exactly one pre-commit hook, so this file exists to chain them.
# See githooks.txt for the symlink convention, the install command, and why
# core.hooksPath is not used.
set -eu

# rev-parse, NOT dirname "$0": the hook is reached through a symlink under
# .git/hooks, so $0's directory is not the repo. Same as deployHook.sh.
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ------------------------------------------------------- schema.org datestamp
./datestampHook.pl

# ----------------------------------------------------- NTP unique-client line
#
# Rewrites the "Around N million unique client IP addresses ... one in every N
# routable IPv4 addresses" sentence from the analytics page ntpstatsgen keeps
# current. No-op off the VPS (the source file is server-only) and no-op when
# neither number moved. See ntpstatsgen.txt and githooks.txt.
./ntpStatHook.pl

# ---------------------------------------------------------------------- feeds
#
# feed.xml/rss.xml: committed artifacts (plain rsync deploy, no build step).
# UNSTAGED GUARD: the generator reads the working tree, so if a source has
# unstaged edits the feeds are left alone and the commit proceeds with a
# warning. See githooks.txt, "THE FOUR STEPS GUARD DIFFERENTLY".
feed_sources=$(git diff --name-only -- \
	'rootdomain/personal/blog.html' 'rootdomain/personal/*.html' \
	| grep -v -e 'personal/feed\.xml$' -e 'personal/rss\.xml$' || true)

if [ -n "$feed_sources" ]; then
	echo "pre-commit: unstaged changes under rootdomain/personal/ —" >&2
	echo "pre-commit: feeds NOT regenerated. Stage or stash, then re-run." >&2
	echo "$feed_sources" | sed 's/^/pre-commit:   /' >&2
else
	./assetsBuild/makeFeed.py
	# Only stage them if they actually moved. `git add` on unchanged files is
	# harmless but noisy in the hook's output, and this keeps a commit that
	# touched no post from silently listing the feeds among its changes.
	for f in rootdomain/personal/feed.xml rootdomain/personal/rss.xml; do
		if ! git diff --quiet -- "$f"; then
			git add "$f"
			echo "pre-commit: re-staged $f"
		fi
	done
fi

# --------------------------------------------------- JSON-LD wall + sitemap
#
# blog.html's JSON-LD block and rootdomain/sitemap.xml, from the same post list
# the feeds use. Shares the feeds' unstaged guard (same $feed_sources). It also
# CHECKS post datelines / BlogPosting dates / JSON-LD validity and ABORTS the
# commit on a mismatch. See githooks.txt ("THE FOUR STEPS GUARD DIFFERENTLY")
# and siteAssets.txt, STRUCTURED DATA.
if [ -n "$feed_sources" ]; then
	echo "pre-commit: JSON-LD and sitemap NOT regenerated either." >&2
else
	./assetsBuild/makeMeta.py
	for f in rootdomain/personal/blog.html rootdomain/sitemap.xml; do
		if ! git diff --quiet -- "$f"; then
			git add "$f"
			echo "pre-commit: re-staged $f"
		fi
	done
fi

# --------------------------------------------------------------- font subsets
#
# The ubuntu804 theme's two DejaVu faces, cut to the themed pages' characters
# (382 kB -> 45 kB). NO UNSTAGED GUARD: a subset built from a half-finished
# tree is merely generous, not a false claim. No-op unless the census changed,
# which keeps two 20 kB blobs out of every commit's history. See githooks.txt,
# "THE FOUR STEPS GUARD DIFFERENTLY".
./assetsBuild/makeFontSubset.py

for f in rootdomain/personal/themes/ubuntu804/f/dejavu.woff2 \
	rootdomain/personal/themes/ubuntu804/f/dejavu-bold.woff2; do
	if ! git diff --quiet -- "$f"; then
		git add "$f"
		echo "pre-commit: re-staged $f"
	fi
done

# ----------------------------------------------------------------- 88x31 wall
#
# Re-encodes the badges (WebP where smaller) and GENERATES the <ul
# class="badges"> block in every page carrying the badges:start/end markers.
# PER-FILE GUARD, because this is the only step that rewrites hand-authored
# files: pages already dirty before it ran get the block on disk but are NOT
# staged, so an unrelated in-progress edit is not swept into the commit; clean
# pages stage normally. See githooks.txt, "THE FOUR STEPS GUARD DIFFERENTLY".
badge_dirty=$(git diff --name-only -- 'rootdomain/personal/*.html' || true)

./assetsBuild/badgeBuild.pl

# The images and the manifest are wholly generated, so they stage without any
# of the above ceremony. -A, not add: a badge dropped from webBadges.csv leaves
# a deletion in badges/ that has to be staged too.
git add -A rootdomain/personal/badges assetsBuild/badgeManifest.txt
if ! git diff --cached --quiet -- rootdomain/personal/badges \
	assetsBuild/badgeManifest.txt; then
	echo "pre-commit: re-staged the badge images"
fi

for f in $(git diff --name-only -- 'rootdomain/personal/*.html' || true); do
	if echo "$badge_dirty" | grep -qxF "$f"; then
		echo "pre-commit: $f had unstaged edits — badge block written to" >&2
		echo "pre-commit:   the file but NOT staged, so this commit does not" >&2
		echo "pre-commit:   sweep up your other changes to it." >&2
	else
		git add "$f"
		echo "pre-commit: re-staged $f (badge wall)"
	fi
done
