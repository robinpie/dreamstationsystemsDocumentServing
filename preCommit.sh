#!/bin/bash
# pre-commit: run every pre-commit step, in order.
#
# .git/hooks/pre-commit used to be a symlink straight to datestampHook.pl,
# because there was only one step. There are two now, and git runs exactly one
# pre-commit hook, so the symlink points here instead and this file calls both:
#
#     datestampHook.pl               schema.org dateModified on staged HTML
#     assetsBuild/makeFeed.py        Atom + RSS for /personal/blog.html
#     assetsBuild/makeFontSubset.py  ubuntu804's DejaVu subsets
#     assetsBuild/badgeBuild.pl      the 88x31 wall: WebP + generated markup
#
# ADDING A STEP: put it below, and make it re-stage anything it rewrites. A
# step that edits a file without `git add`ing it produces a commit whose
# contents do not match what the hook computed.
#
# See githooks.txt for the symlink convention and why core.hooksPath is not
# used. Install with:
#
#     ln -sf ../../preCommit.sh .git/hooks/pre-commit
set -eu

# NOT dirname "$0": git invokes this through the .git/hooks/pre-commit
# symlink, so $0 is that path and dirname lands in .git/hooks, where none of
# the scripts below exist. `git rev-parse --show-toplevel` resolves the repo
# root whatever path the hook was reached by — the same thing deployHook.sh
# does, and for the same reason.
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ------------------------------------------------------- schema.org datestamp
./datestampHook.pl

# ---------------------------------------------------------------------- feeds
#
# feed.xml and rss.xml are generated from blog.html and the og:description of
# each post, so they are committed artifacts: the deploy is a plain rsync of
# rootdomain/ and has no build step that could produce them later.
#
# THE UNSTAGED GUARD, matching datestampHook.pl's: the generator reads the
# WORKING TREE, not the index. If a source file has unstaged edits, the feed
# built from it would describe posts this commit does not contain — so the
# feeds are left exactly as they are and the commit proceeds. This is a
# warning, not an abort: an unrelated commit should not be blocked by a draft
# sitting in the tree.
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

# --------------------------------------------------------------- font subsets
#
# The ubuntu804 theme's two DejaVu faces, cut down to the characters the seven
# themed pages actually use (382 kB -> 45 kB). Committed artifacts for the same
# reason the feeds are: the deploy is a plain rsync of rootdomain/ with no
# build step that could produce them later.
#
# NO UNSTAGED GUARD HERE, unlike the feeds above, and the difference is not an
# oversight. A feed built from a half-finished tree makes a FALSE CLAIM — it
# announces posts the commit does not contain, to readers who cache it. A font
# subset built from a half-finished tree is merely GENEROUS: it carries a few
# glyphs for text that is not committed yet, which costs bytes and breaks
# nothing. The failure modes are not comparable, so the guard that is right for
# one is needless friction for the other.
#
# The generator is a no-op unless the character census actually changed, so a
# commit that touches no themed page leaves these binaries alone and out of the
# diff. That matters more than usual here: without it every commit would put
# two new 20 kB blobs into git history.
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
# Re-encodes the badges to WebP where that is smaller (see badgeBuild.pl for
# why "where smaller" and not "always"), then GENERATES the <ul class="badges">
# block in every page carrying the badges:start/end markers. Committed
# artifacts, same reasoning as the feeds and the font subsets: plain rsync
# deploy, no build step downstream.
#
# It is a no-op on a commit that touches no badge — a source sha256 that
# matches the manifest skips the encoders entirely, and the generated markup is
# byte-identical, so nothing gets re-staged and nothing enters the diff.
#
# THE GUARD HERE IS NOT THE FEEDS' GUARD, and not the font subsets' absence of
# one. This step is the only one that rewrites HAND-AUTHORED FILES: it edits
# eight .html pages that you also edit. `git add` on one of those would sweep
# an unrelated in-progress edit sitting in the same file into this commit —
# a thing no generator should ever do, and one you would not notice until you
# read the commit later.
#
# So the pages that were already dirty BEFORE the generator ran are recorded
# first, and those are the ones it refuses to stage. The wall is still written
# into them on disk, so nothing is lost and the next commit picks it up; it
# just is not staged on your behalf. Pages that were clean are staged normally,
# because for those the badge block is provably the only change.
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
