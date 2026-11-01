#!/bin/bash
# Commit everything, promote, push. Fast when there is nothing to do:
#
#   - no --allow-empty: git runs the pre-commit hook BEFORE deciding there is
#     "nothing to commit", so the hooks still get their chance to pick up a
#     moved NTP figure or a new day's datestamp. If they change nothing, no
#     commit is made and stageSite.sh (post-commit) does not run.
#   - promote is skipped when HEAD is what the last clean promote made live
#     (.git/promote-last, written by promoteSite.sh).
#   - push is skipped when the upstream ref already equals HEAD (local check,
#     no network).
#
#   ./dangerouslyDeployImmediately.sh [--force]
#
# --force promotes regardless of the stamp (to undo hand edits under /srv or
# /etc) and is passed on to promoteSite.sh. See githooks.txt, "promote stamps".

DIDFAIL=0
FORCE=0
for arg in "$@"; do
	case "$arg" in
	--force) FORCE=1 ;;
	*)
		echo "usage: $0 [--force]" >&2
		exit 2
		;;
	esac
done

cd "$(dirname "$0")" || exit 1

before="$(git rev-parse HEAD)"
git add -A || DIDFAIL=1
if ! git commit -am "automatic commit: from the dangerouslyDeployImmediately.sh script"; then
	# "Nothing to commit" also exits 1. Tell it apart from a real failure (a
	# hook abort) by whether anything is left over: a no-op leaves a clean tree.
	if [ "$(git rev-parse HEAD)" != "$before" ] || [ -n "$(git status --porcelain)" ]; then
		DIDFAIL=1
	fi
fi

head="$(git rev-parse HEAD)"
stamp="$(git rev-parse --absolute-git-dir)/promote-last"

if [ "$FORCE" = 1 ]; then
	./promoteSite.sh --force || DIDFAIL=1
elif [ "$(cat "$stamp" 2>/dev/null)" = "$head" ] && [ -z "$(git status --porcelain)" ]; then
	echo "Live is already $(git rev-parse --short HEAD); promote skipped (--force to redo)."
else
	./promoteSite.sh || DIDFAIL=1
fi

if [ "$(git rev-parse '@{u}' 2>/dev/null)" = "$head" ]; then
	echo "origin is already at $(git rev-parse --short HEAD); push skipped."
else
	git push # nbd if this fails
fi

exit $DIDFAIL
