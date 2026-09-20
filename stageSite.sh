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
# later promote. See githooks.txt for why this is repeated in promoteSite.sh.
if compgen -G "$ROOT/cgi/*.cgi" >/dev/null; then
	for f in "$ROOT"/cgi/*.cgi; do
		if ! perl -c "$f" >/dev/null 2>&1; then
			echo "ABORT: $(basename "$f") fails syntax check — nothing staged." >&2
			perl -c "$f" || true # show the user why
			exit 1
		fi
	done
fi

# Every script under statusSample/, including the half that runs on starport.
for f in "$ROOT"/statusSample/*.sh "$ROOT"/statusSample/starport/*.sh; do
	[ -f "$f" ] || continue
	if ! bash -n "$f" 2>/dev/null; then
		echo "ABORT: ${f#"$ROOT"/} fails syntax check — nothing staged." >&2
		bash -n "$f" || true
		exit 1
	fi
done

# -------------------------------------------------------------------- content
#
# No acme-challenge/ntpstats carve-out here (unlike promote): neither exists
# in this tree, so staging owns every byte under it and a plain --delete is fine.
sudo rsync -a --delete "$ROOT/rootdomain/" "$STAGING/"

sudo chown -R root:root "$STAGING/"
sudo chmod -R u=rwX,go=rX "$STAGING/"

echo "Staged rootdomain/ → $STAGING  (https://staging.dreamstation.systems)"
echo "Run ./promoteSite.sh to go live."
