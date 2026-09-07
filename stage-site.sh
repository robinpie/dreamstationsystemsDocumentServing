#!/bin/bash
# Stage: rsyncs rootdomain/ to /srv/httpstaging for preview. Runs on every
# commit/merge (post-commit/post-merge hooks); touches nothing live. See
# githooks.txt for the full stage/promote split.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGING=/srv/httpstaging

# --------------------------------------------------------------- syntax gates
#
# Compile-time checks only, so a broken commit fails now rather than during a
# later promote. See githooks.txt for why this is repeated in promote-site.sh.
if compgen -G "$ROOT/cgi/*.cgi" >/dev/null; then
	for f in "$ROOT"/cgi/*.cgi; do
		if ! perl -c "$f" >/dev/null 2>&1; then
			echo "ABORT: $(basename "$f") fails syntax check — nothing staged." >&2
			perl -c "$f" || true # show the user why
			exit 1
		fi
	done
fi

if [ -f "$ROOT/status-sample/status-sample.sh" ]; then
	if ! bash -n "$ROOT/status-sample/status-sample.sh" 2>/dev/null; then
		echo "ABORT: status-sample.sh fails syntax check — nothing staged." >&2
		bash -n "$ROOT/status-sample/status-sample.sh" || true
		exit 1
	fi
fi

# -------------------------------------------------------------------- content
#
# No acme-challenge/ntpstats carve-out here (unlike promote): neither exists
# in this tree, so staging owns every byte under it and a plain --delete is fine.
sudo rsync -a --delete "$ROOT/rootdomain/" "$STAGING/"

sudo chown -R root:root "$STAGING/"
sudo chmod -R u=rwX,go=rX "$STAGING/"

echo "Staged rootdomain/ → $STAGING  (https://staging.dreamstation.systems)"
echo "Run ./promote-site.sh to go live."
